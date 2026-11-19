import Foundation
import SwiftUI

enum Category: String, CaseIterable, Codable, Identifiable {
    case read = "Почитать", watch = "Посмотреть", doIt = "Сделать", idea = "Идея"
    var id: Self { self }

    var label: String {
        switch self {
        case .read: return "Read"
        case .watch: return "Watch"
        case .doIt: return "Do"
        case .idea: return "Idea"
        }
    }
}

enum EntryStatus: String, Codable {
    case inbox, completed, archived
}

struct Entry: Codable, Identifiable {
    var id = UUID()
    var title: String
    var url: URL?
    var category: Category?
    var note: String?
    var linkDescription: String?
    var createdAt = Date()
    var status: EntryStatus = .inbox
    var titleWasEdited = false

    var siteTag: String? { url.flatMap(LinkMetadata.siteTag(for:)) }
}

extension Entry {
    private enum CodingKeys: String, CodingKey {
        case id, title, url, category, note, linkDescription, createdAt, status, titleWasEdited
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        title = try fields.decode(String.self, forKey: .title)
        url = try fields.decodeIfPresent(URL.self, forKey: .url)
        category = try fields.decodeIfPresent(Category.self, forKey: .category)
        note = try fields.decodeIfPresent(String.self, forKey: .note)
        linkDescription = try fields.decodeIfPresent(String.self, forKey: .linkDescription)
        createdAt = try fields.decode(Date.self, forKey: .createdAt)
        status = try fields.decode(EntryStatus.self, forKey: .status)
        titleWasEdited = try fields.decodeIfPresent(Bool.self, forKey: .titleWasEdited) ?? false
    }
}

func webURL(_ text: String) -> URL? {
    guard !text.contains(where: { $0.isWhitespace }),
          let url = URL(string: text), let scheme = url.scheme?.lowercased(),
          ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty else { return nil }
    return url
}

enum AddEntryResult {
    case saved, duplicate(Entry), failed
}

private func linkIdentity(_ url: URL) -> String {
    if let youtube = LinkMetadata.canonicalYouTubeURL(for: url) { return youtube.absoluteString }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url.absoluteString
    }
    components.host = components.host?.lowercased()
    components.scheme = components.scheme?.lowercased()
    if components.path.isEmpty { components.path = "/" }
    let originalQuery = components.percentEncodedQueryItems
    if let originalQuery {
        let clean = originalQuery.filter { !$0.name.lowercased().hasPrefix("utm_") }
        if clean.count != originalQuery.count { components.percentEncodedQueryItems = clean.isEmpty ? nil : clean }
    }
    return components.string ?? url.absoluteString
}

@MainActor
final class Inbox: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published var error: String?
    @Published private(set) var deleted: Entry?
    @Published private(set) var isRefreshingTitles = false
    private var queuedTitles: [UUID: Bool] = [:]
    private var checkedTitles: [UUID: URL] = [:]

    var canRefreshTitles: Bool { entries.contains { titleURL(for: $0) != nil } }
    var onChange: (() -> Void)?
    static let automaticTitlesKey = "autoFetchLinkTitles"
    private var fetchAutomatically: Bool { UserDefaults.standard.object(forKey: Self.automaticTitlesKey) as? Bool ?? true }
    private let store: InboxStore
    private var snapshot: InboxStore.Snapshot?
    var count: Int { entries.lazy.filter { $0.status == .inbox }.count }

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Laterfold/inbox.json")) {
        store = InboxStore(file: file)
        loadIfNeeded()
    }

    private func loadIfNeeded() {
        guard snapshot == nil else { return }
        do {
            apply(try store.read())
        } catch {
            self.error = "Could not read the inbox at \(store.file.path). \(error.localizedDescription)"
        }
    }

    private func apply(_ snapshot: InboxStore.Snapshot) {
        self.snapshot = snapshot
        entries = snapshot.entries
        onChange?()
    }

    @discardableResult
    private func persist(_ next: [Entry]) -> Bool {
        guard let snapshot else { return false }
        do {
            apply(try store.write(next, replacing: snapshot.revision))
            error = nil
            return true
        } catch InboxStore.Failure.changed(let current) {
            apply(current)
            error = InboxStore.Failure.changed(current).localizedDescription
            return false
        } catch {
            self.error = "Could not save changes. \(error.localizedDescription)"
            return false
        }
    }

    private func duplicate(of url: URL, excluding id: UUID? = nil) -> Entry? {
        let identity = linkIdentity(url)
        return entries.first { $0.id != id && $0.url.map(linkIdentity) == identity }
    }

    func add(_ input: String, category: Category?) -> AddEntryResult {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .failed }
        loadIfNeeded()
        let url = webURL(title)
        if let url, let existing = duplicate(of: url) { return .duplicate(existing) }
        let entry = Entry(title: title, url: url, category: category)
        guard persist(entries + [entry]) else { return .failed }
        enqueueTitles([entry], manual: false)
        return .saved
    }

    @discardableResult
    func update(_ id: UUID, _ transform: (inout Entry) -> Void) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        var next = entries
        transform(&next[index])
        return persist(next)
    }

    func edit(_ draft: Entry, originalTitle: String) -> Bool {
        guard let current = entries.first(where: { $0.id == draft.id }) else { return false }
        let changedTitle = draft.title != originalTitle
        let changedURL = draft.url != current.url
        if changedURL, let url = draft.url, let existing = duplicate(of: url, excluding: draft.id) {
            error = "That link is already saved as “\(existing.title)”."
            return false
        }
        let saved = update(draft.id) {
            if changedTitle {
                $0.titleWasEdited = true
                $0.title = draft.title
            } else if changedURL, !$0.titleWasEdited, let url = draft.url {
                $0.title = url.absoluteString
            }
            if changedURL { $0.linkDescription = nil }
            $0.url = draft.url
            $0.category = draft.category
            $0.note = draft.note
        }
        if saved, changedURL, let updated = entries.first(where: { $0.id == draft.id }), !updated.titleWasEdited {
            enqueueTitles([updated], manual: false)
        }
        return saved
    }

    func refreshVisibleLinkTitles() {
        enqueueTitles(entries.filter { $0.status == .inbox }, manual: false)
    }

    func refreshLinkTitles() {
        enqueueTitles(entries, manual: true)
    }

    func delete(_ entry: Entry) {
        guard let current = entries.first(where: { $0.id == entry.id }),
              persist(entries.filter { $0.id != entry.id }) else { return }
        deleted = current
    }

    func undoDelete() {
        guard let deleted, persist(entries + [deleted]) else { return }
        self.deleted = nil
    }

    private func titleURL(for entry: Entry) -> URL? {
        guard !entry.titleWasEdited, let url = entry.url,
              LinkMetadata.allowsRequest(to: url),
              LinkMetadata.needsTitle(entry.title, for: url) else { return nil }
        return url
    }

    private func enqueueTitles(_ candidates: [Entry], manual: Bool) {
        for entry in candidates {
            guard let url = titleURL(for: entry) else { continue }
            let youtube = LinkMetadata.canonicalYouTubeURL(for: url) != nil
            if !manual && checkedTitles[entry.id] == url { continue }
            guard manual || fetchAutomatically || youtube else { continue }
            queuedTitles[entry.id] = manual || queuedTitles[entry.id] == true
        }
        guard !isRefreshingTitles, !queuedTitles.isEmpty else { return }
        isRefreshingTitles = true
        Task { [weak self] in await self?.drainTitles() }
    }

    private func drainTitles() async {
        defer { isRefreshingTitles = false }
        while let (id, manual) = queuedTitles.first {
            queuedTitles.removeValue(forKey: id)
            guard let entry = entries.first(where: { $0.id == id }),
                  let url = titleURL(for: entry) else { continue }
            let allowPageFetch = manual || fetchAutomatically
            let youtube = LinkMetadata.canonicalYouTubeURL(for: url) != nil
            guard allowPageFetch || youtube else { continue }
            checkedTitles[id] = url
            guard let preview = await LinkMetadata.preview(for: url, allowPageFetch: allowPageFetch),
                  let latest = entries.first(where: { $0.id == id }),
                  titleURL(for: latest) == url,
                  preview.title != nil || (preview.description != nil && preview.description != latest.linkDescription)
            else { continue }
            update(id) {
                if let title = preview.title { $0.title = title }
                if let description = preview.description { $0.linkDescription = description }
            }
        }
    }
}
