import AppKit
import SwiftUI

struct EditEntry: View {
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
