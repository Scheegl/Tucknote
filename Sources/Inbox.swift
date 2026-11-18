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
    var site: String?
    var category: Category?
    var note: String?
    var createdAt = Date()
    var status: EntryStatus = .inbox
    var titleWasEdited = false

    var siteTag: String? { url.flatMap(LinkMetadata.siteTag(for:)) }
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
    private var fetching: Set<UUID> = []

    var canRefreshTitles: Bool {
        entries.contains { entry in
            !entry.titleWasEdited && (entry.url.map {
                LinkMetadata.allowsRequest(to: $0) && LinkMetadata.needsTitle(entry.title, for: $0)
            } ?? false)
        }
    }
    var onChange: (() -> Void)?
    static let automaticTitlesKey = "autoFetchLinkTitles"
    private var fetchAutomatically: Bool { UserDefaults.standard.bool(forKey: Self.automaticTitlesKey) }
    private let file: URL
    private var loaded = false
    var count: Int { entries.lazy.filter { $0.status == .inbox }.count }

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Laterfold/inbox.json")) {
        self.file = file
        reload()
    }

    func reload() {
        guard !loaded else { return }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
            loaded = true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            loaded = true
        } catch {
            self.error = "Could not read the inbox. The original file is at \(file.path). \(error.localizedDescription)"
        }
        onChange?()
    }

    @discardableResult
    private func persist(_ next: [Entry]) -> Bool {
        reload()
        guard loaded else { return false }
        do {
            let directory = file.deletingLastPathComponent()
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            if attributes[.posixPermissions] as? Int != 0o700 {
                try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            entries = next
            onChange?()
            return true
        } catch {
            self.error = "Could not save changes. \(error.localizedDescription)"
            return false
        }
    }

    func add(_ input: String, category: Category?) -> AddEntryResult {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .failed }
        reload()
        let url = webURL(title)
        if let url {
            let identity = linkIdentity(url)
            if let existing = entries.first(where: { $0.url.map(linkIdentity) == identity }) {
                return .duplicate(existing)
            }
        }
        let entry = Entry(title: title, url: url, site: url?.host, category: category)
        guard persist(entries + [entry]) else { return .failed }
        if fetchAutomatically { fetchTitle(for: entry) }
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
        let saved = update(draft.id) {
            if changedTitle {
                $0.titleWasEdited = true
                $0.title = draft.title
            } else if changedURL, !$0.titleWasEdited, let url = draft.url {
                $0.title = url.absoluteString
            }
            $0.url = draft.url
            $0.site = draft.url?.host
            $0.category = draft.category
            $0.note = draft.note
        }
        if saved, changedURL, fetchAutomatically, let updated = entries.first(where: { $0.id == draft.id }), !updated.titleWasEdited {
            fetchTitle(for: updated)
        }
        return saved
    }

    func refreshLinkTitles() {
        guard !isRefreshingTitles, canRefreshTitles else { return }
        isRefreshingTitles = true
        let pending = entries
        Task { [weak self] in
            guard let self else { return }
            for entry in pending { await self.resolveTitle(for: entry) }
            self.isRefreshingTitles = false
        }
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

    private func fetchTitle(for entry: Entry) {
        Task { [weak self] in await self?.resolveTitle(for: entry) }
    }

    private func resolveTitle(for entry: Entry) async {
        guard let url = entry.url,
              let current = entries.first(where: { $0.id == entry.id }),
              current.url == url, !current.titleWasEdited,
              LinkMetadata.needsTitle(current.title, for: url),
              fetching.insert(entry.id).inserted else { return }
        defer { fetching.remove(entry.id) }
        let title = await LinkMetadata.title(for: url)
        guard let latest = entries.first(where: { $0.id == entry.id }), !latest.titleWasEdited else { return }
        if latest.url != url {
            if fetchAutomatically {
                fetching.remove(entry.id)
                fetchTitle(for: latest)
            }
        } else if let title, LinkMetadata.needsTitle(latest.title, for: url) {
            update(entry.id) { $0.title = title }
        }
    }
}
