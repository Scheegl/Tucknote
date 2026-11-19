import AppKit
import SwiftUI

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
            if draft.waitingCount > 0 {
                HStack {
                    Text("\(draft.waitingCount) incoming draft(s) waiting").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Next") { draft.showNextIfEmpty() }
                        .disabled(!draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Save or clear the current draft first")
                }
                .font(.callout)
            }
            if let duplicate {
                HStack(spacing: 8) {
                    Label("Already saved", systemImage: "link.badge.plus")
                    Text(duplicate.title).lineLimit(1).foregroundStyle(.secondary).help(duplicate.title)
                    Spacer(minLength: 0)
                    Button("Show Entry") {
                        draft.clearAndAdvance()
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
            draft.clearAndAdvance()
            focused = true
        case .duplicate(let existing):
            duplicate = existing
        case .failed:
            break
        }
    }
}
