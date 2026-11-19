import AppKit
import SwiftUI

struct EntryList: View {
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

struct CategoryPicker: View {
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
        if let canonical = LinkMetadata.canonicalYouTubeURL(for: url),
           let id = URLComponents(url: canonical, resolvingAgainstBaseURL: false)?.queryItems?.first {
            return "YouTube \(id.name == "list" ? "playlist" : "video") · \(id.value ?? "")"
        }
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
                .help([title, entry.linkDescription, url.absoluteString, entry.note].compactMap { $0 }.joined(separator: "\n"))
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

struct InboxFeedback: View {
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
