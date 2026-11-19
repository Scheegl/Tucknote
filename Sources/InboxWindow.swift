import AppKit
import SwiftUI

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
        let showAllSections = !query.isEmpty || source != nil
        let section = self.section ?? .inbox
        return inbox.entries.filter { entry in
            guard showAllSections else { return section.includes(entry) }
            guard source == nil || source == entry.siteTag else { return false }
            let fields = [entry.title, entry.url?.absoluteString, entry.siteTag, entry.linkDescription, entry.note, entry.category?.label]
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
            let results = entries
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
                if results.isEmpty {
                    Text(showingResults ? "No matches" : "This section is empty")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EntryList(inbox: inbox, entries: results, selected: $selected, compact: false,
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
