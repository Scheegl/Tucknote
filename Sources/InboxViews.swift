import AppKit
import SwiftUI

@MainActor
final class CaptureDraft: ObservableObject {
    @Published var input = ""
    @Published var category: Category?
}

struct CaptureView: View {
    @ObservedObject var inbox: Inbox
    @ObservedObject var draft: CaptureDraft
    var openInbox: () -> Void
    var navigate: (InboxDestination) -> Void
    var openSettings: () -> Void
    @FocusState private var focused: Bool
    @State private var editing: Entry?
    @State private var selected: UUID?
    @State private var duplicate: Entry?

    private var entries: [Entry] {
        inbox.entries.filter { $0.status == .inbox }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Group {
            if let editing {
                EditEntry(inbox: inbox, draft: editing) { self.editing = nil }
            } else {
                capture
            }
        }
        .frame(width: 420, height: 430)
        .modifier(TucknoteSurface())
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BrandMark()
                Text("Tucknote").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Settings")
            }
            HStack {
                TextField("A thought, task, or link", text: $draft.input)
                    .focused($focused)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            CategoryPicker(category: $draft.category)
                .frame(maxWidth: 200)
            if let duplicate {
                HStack(spacing: 8) {
                    Label("Already saved", systemImage: "link.badge.plus")
                    Text(duplicate.title).lineLimit(1).foregroundStyle(.secondary).help(duplicate.title)
                    Spacer(minLength: 0)
                    Button("Show Entry") {
                        draft.input = ""
                        draft.category = nil
                        navigate(.entry(duplicate.id))
                    }
                }
                .font(.callout)
            }
            Divider()
            if entries.isEmpty {
                Text("Your inbox is empty").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EntryList(inbox: inbox, entries: entries, selected: $selected, compact: true,
                          showStatus: false, keyboardEnabled: true,
                          focusList: { focused = false }, edit: { editing = $0 },
                          filterSource: { navigate(.source($0)) })
            }
            InboxFeedback(inbox: inbox)
            HStack {
                Button("Open Inbox", action: openInbox)
                Spacer()
                Button("Quit Tucknote") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(18)
        .onAppear { focused = true }
        .onChange(of: focused) { if $0 { selected = nil } }
        .onChange(of: draft.input) { _ in duplicate = nil; selected = nil }
        .onReceive(NotificationCenter.default.publisher(for: .focusCapture)) { _ in
            selected = nil
            focused = true
        }
    }

    private func add() {
        switch inbox.add(draft.input, category: draft.category) {
        case .saved:
            draft.input = ""
            draft.category = nil
            focused = true
        case .duplicate(let existing):
            duplicate = existing
        case .failed:
            break
        }
    }
}

private enum SectionFilter: Hashable {
    case inbox, category(Category), completed, archived

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .category(let category): return category == .idea ? "Ideas" : category.label
        case .completed: return "Completed"
        case .archived: return "Archive"
        }
    }

    func includes(_ entry: Entry) -> Bool {
        switch self {
        case .inbox: return entry.status == .inbox
        case .category(let category): return entry.status == .inbox && entry.category == category
        case .completed: return entry.status == .completed
        case .archived: return entry.status == .archived
        }
    }
}

struct InboxWindow: View {
    @ObservedObject var inbox: Inbox
    @ObservedObject var navigation: InboxNavigation
    @State private var section: SectionFilter? = .inbox
    @State private var search = ""
    @State private var source: String?
    @State private var editing: Entry?
    @State private var selected: UUID?
    @FocusState private var searchFocused: Bool

    private var words: [String] { search.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var showingResults: Bool { !words.isEmpty || source != nil }

    private var entries: [Entry] {
        let query = words
        return inbox.entries.filter { entry in
            guard showingResults else { return (section ?? .inbox).includes(entry) }
            guard source == nil || source == entry.siteTag else { return false }
            let fields = [entry.title, entry.url?.absoluteString, entry.siteTag, entry.note, entry.category?.label]
                .compactMap { $0 }
            return query.allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
        }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Inbox", systemImage: "tray").tag(SectionFilter.inbox)
                ForEach(Category.allCases) { category in
                    Text(category == .idea ? "Ideas" : category.label).tag(SectionFilter.category(category))
                }
                Label("Completed", systemImage: "checkmark.circle").tag(SectionFilter.completed)
                Label("Archive", systemImage: "archivebox").tag(SectionFilter.archived)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 185)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    BrandMark()
                    Text(showingResults ? "Search Results" : section?.title ?? "Inbox")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Spacer()
                    TextField("Search all entries", text: $search)
                        .focused($searchFocused)
                        .frame(maxWidth: 220)
                    if !search.isEmpty {
                        Button { search = ""; selected = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear search")
                        .accessibilityLabel("Clear search")
                    }
                    Button {
                        inbox.refreshLinkTitles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(inbox.isRefreshingTitles || !inbox.canRefreshTitles)
                    .help(inbox.isRefreshingTitles ? "Refreshing link titles…" : "Refresh Link Titles")
                    .accessibilityLabel("Refresh Link Titles")
                }
                if let source {
                    Button {
                        self.source = nil
                        selected = nil
                    } label: {
                        Label(source, systemImage: "xmark.circle.fill")
                    }
                    .help("Clear source filter")
                    .accessibilityLabel("Clear source filter for \(source)")
                }
                if entries.isEmpty {
                    Text(showingResults ? "No matches" : "This section is empty")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EntryList(inbox: inbox, entries: entries, selected: $selected, compact: false,
                              showStatus: showingResults, keyboardEnabled: editing == nil,
                              focusList: { searchFocused = false }, edit: { editing = $0 },
                              filterSource: { source = $0; selected = nil })
                }
                InboxFeedback(inbox: inbox)
            }
            .padding(20)
            .modifier(TucknoteSurface())
        }
        .frame(minWidth: 650, minHeight: 390)
        .onChange(of: search) { _ in
            if searchFocused { selected = nil }
        }
        .onChange(of: searchFocused) { if $0 { selected = nil } }
        .onReceive(navigation.$destination) { destination in
            guard let destination else { return }
            searchFocused = false
            search = ""
            switch destination {
            case .source(let tag):
                source = tag
                selected = nil
            case .entry(let id):
                guard let entry = inbox.entries.first(where: { $0.id == id }) else { return }
                source = nil
                switch entry.status {
                case .inbox: section = .inbox
                case .completed: section = .completed
                case .archived: section = .archived
                }
                selected = id
            }
        }
        .sheet(item: $editing) { entry in
            EditEntry(inbox: inbox, draft: entry) { editing = nil }
                .modifier(TucknoteSurface())
        }
    }
}

private struct EntryList: View {
    @ObservedObject var inbox: Inbox
    let entries: [Entry]
    @Binding var selected: UUID?
    let compact: Bool
    let showStatus: Bool
    let keyboardEnabled: Bool
    let focusList: () -> Void
    let edit: (Entry) -> Void
    let filterSource: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        EntryRow(inbox: inbox, entry: entry, selected: selected == entry.id,
                                 compact: compact, showStatus: showStatus, filterSource: filterSource,
                                 edit: { edit(entry) })
                            .id(entry.id)
                        Divider()
                    }
                }
            }
            .onAppear { if let selected { proxy.scrollTo(selected) } }
            .onChange(of: selected) { if let id = $0 { proxy.scrollTo(id) } }
        }
        .background {
            EntryKeyboard { event in
                guard keyboardEnabled else { return false }
                return EntryKeyboard.handle(event, entries: entries, selected: $selected,
                    focusList: focusList, edit: edit, archive: archive)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func archive(_ entry: Entry) {
        guard inbox.update(entry.id, { $0.status = .archived }), !showStatus else { return }
        let remaining = entries.filter { $0.id != entry.id }
        let index = entries.firstIndex { $0.id == entry.id } ?? 0
        selected = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

private struct CategoryPicker: View {
    @Binding var category: Category?

    var body: some View {
        Picker("Category", selection: $category) {
            Text("No category").tag(nil as Category?)
            ForEach(Category.allCases) { Text($0.label).tag(Optional($0)) }
        }
        .labelsHidden()
        .accessibilityLabel("Category")
    }
}

private struct EntryRow: View {
    @ObservedObject var inbox: Inbox
    let entry: Entry
    let selected: Bool
    let compact: Bool
    let showStatus: Bool
    let filterSource: (String) -> Void
    var edit: () -> Void

    private var title: String {
        guard let url = entry.url, !entry.titleWasEdited, LinkMetadata.needsTitle(entry.title, for: url) else {
            return entry.title
        }
        if LinkMetadata.youtubeEmbedURL(for: url) != nil { return "YouTube link" }
        return url.host.map { $0 + (url.path == "/" ? "" : url.path) } ?? entry.title
    }

    var body: some View {
        HStack(spacing: 6) {
            if entry.status == .inbox || entry.status == .completed {
                let completed = entry.status == .completed
                Button {
                    setStatus(completed ? .inbox : .completed)
                } label: {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.borderless)
                .help(completed ? "Move to Inbox" : "Mark as Completed")
                .accessibilityLabel(completed ? "Move to Inbox" : "Mark as Completed")
            } else {
                Color.clear.frame(width: 25, height: 24).accessibilityHidden(true)
            }
            if let url = entry.url, webURL(url.absoluteString) != nil {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help(title + "\n" + url.absoluteString + (entry.note.map { "\n" + $0 } ?? ""))
                .contextMenu { entryMenu }
            } else {
                Text(title).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(title + (entry.note.map { "\n" + $0 } ?? ""))
            }
            if let tag = entry.siteTag {
                Button { filterSource(tag) } label: {
                    Text(tag).font(.caption2.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .frame(maxWidth: 88)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .help("Filter by \(tag)")
                .accessibilityLabel("Filter by \(tag)")
                .contextMenu { entryMenu }
            }
            if let category = entry.category {
                Text(category.label).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
            }
            if showStatus, entry.status == .archived {
                Image(systemName: "archivebox").foregroundStyle(.secondary)
                    .help("Archived").accessibilityLabel("Archived")
            }
            if compact {
                Menu { entryMenu } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Entry Actions")
                    .accessibilityLabel("Entry Actions")
            } else {
                action("Edit", icon: "pencil", perform: edit)
                if entry.status == .inbox {
                    action("Archive", icon: "archivebox") { setStatus(.archived) }
                } else if entry.status == .archived {
                    action("Move to Inbox", icon: "arrow.uturn.backward") { setStatus(.inbox) }
                }
                action("Delete", icon: "trash") { inbox.delete(entry) }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background {
            if selected { RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.15)) }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { entryMenu }
    }

    @ViewBuilder
    private var entryMenu: some View {
        Button("Edit Entry…", action: edit)
        Picker("Category", selection: Binding(
            get: { entry.category },
            set: { category in inbox.update(entry.id) { $0.category = category } }
        )) {
            Text("No category").tag(nil as Category?)
            ForEach(Category.allCases) { Text($0.label).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
        if let url = entry.url, webURL(url.absoluteString) != nil {
            Divider()
            Button("Open Link") { NSWorkspace.shared.open(url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        Divider()
        if entry.status == .inbox {
            Button("Mark as Completed") { setStatus(.completed) }
            Button("Archive") { setStatus(.archived) }
        } else {
            Button("Move to Inbox") { setStatus(.inbox) }
        }
        Divider()
        Button("Delete", role: .destructive) { inbox.delete(entry) }
    }

    private func setStatus(_ status: EntryStatus) {
        inbox.update(entry.id) { $0.status = status }
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: icon).frame(width: 18, height: 20) }
            .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}

private struct InboxFeedback: View {
    @ObservedObject var inbox: Inbox

    var body: some View {
        if let error = inbox.error {
            VStack(alignment: .leading, spacing: 6) {
                Text(error).font(.caption).textSelection(.enabled)
                Button("Dismiss") { inbox.error = nil }.buttonStyle(.borderless)
            }
        }
        if inbox.deleted != nil {
            HStack {
                Text("Entry deleted").foregroundStyle(.secondary)
                Spacer()
                Button("Undo") { inbox.undoDelete() }
            }
            .font(.callout)
        }
    }
}

private struct EditEntry: View {
    @ObservedObject var inbox: Inbox
    @State var draft: Entry
    var dismiss: () -> Void
    @State private var originalTitle = ""
    @State private var address = ""
    @State private var note = ""

    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var invalidAddress: Bool { !trimmedAddress.isEmpty && webURL(trimmedAddress) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Entry").font(.headline)
            TextField("Title", text: $draft.title)
            TextField("URL", text: $address)
            if invalidAddress { Text("Enter an HTTP or HTTPS link").font(.caption).foregroundStyle(.red) }
            CategoryPicker(category: $draft.category)
            Text("Note").font(.callout)
            TextEditor(text: $note).font(.body).frame(height: 100).border(.quaternary)
            if let error = inbox.error { Text(error).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    draft.title = trimmedTitle
                    draft.url = webURL(trimmedAddress)
                    draft.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                    if inbox.edit(draft, originalTitle: originalTitle) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty || invalidAddress)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear {
            originalTitle = draft.title
            address = draft.url?.absoluteString ?? ""
            note = draft.note ?? ""
        }
    }
}
