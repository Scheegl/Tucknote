import Foundation

@main
enum InboxChecks {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = root.appendingPathComponent("Inbox")
        let file = directory.appendingPathComponent("inbox.json")
        let inbox = Inbox(file: file)
        guard case .saved = inbox.add("Plain text", category: .read) else {
            preconditionFailure("Could not save a local note")
        }
        let reopened = Inbox(file: file)
        precondition(reopened.entries.first?.title == "Plain text")
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        precondition(attributes[.posixPermissions] as? Int == 0o700)

        let https = URL(string: "https://example.org/story")!
        let http = URL(string: "http://example.org/story")!
        let credentials = URL(string: "https://user:password@example.org/story")!
        precondition(LinkMetadata.allowsRequest(to: https))
        precondition(!LinkMetadata.allowsRequest(to: http))
        precondition(!LinkMetadata.allowsRequest(to: credentials))
        let insecureTitle = await LinkMetadata.title(for: http)
        precondition(insecureTitle == nil)
        precondition(LinkMetadata.htmlTitle("<meta property=\"og:title\" content=\"Tea &amp; biscuits\">", for: https)
                     == "Tea & biscuits")

        let preview = LinkMetadata.htmlPreview(
            #"<title>Test article</title><meta name='description' content='A small &amp; readable summary'>"#,
            for: https
        )
        precondition(preview == LinkMetadata.Preview(title: "Test article", description: "A small & readable summary"))

        let long = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
        let short = URL(string: "https://youtu.be/jNQXAC9IVRw?t=4")!
        precondition(LinkMetadata.canonicalYouTubeURL(for: long) == LinkMetadata.canonicalYouTubeURL(for: short))
        let stored = Entry(title: "Saved video", url: long, status: .archived)
        try JSONEncoder().encode([stored]).write(to: file, options: .atomic)
        let duplicates = Inbox(file: file)
        guard case .duplicate(let original) = duplicates.add(short.absoluteString, category: nil) else {
            preconditionFailure("An archived YouTube link was saved twice")
        }
        precondition(original.id == stored.id && duplicates.entries.count == 1)
        try checkStorage(root)
        checkCapture()
        try checkUpdates()
        print("Tucknote checks passed")
    }

    @MainActor
    private static func checkStorage(_ root: URL) throws {
        let file = root.appendingPathComponent("Concurrent/inbox.json")
        let before = Inbox(file: file)
        let other = Inbox(file: file)
        guard case .saved = before.add("First", category: nil),
              case .failed = other.add("Second", category: nil) else {
            preconditionFailure("A stale write was not detected")
        }
        precondition(other.entries.map(\.title) == ["First"])
        guard case .saved = other.add("Second", category: nil) else {
            preconditionFailure("The write did not recover after refresh")
        }
        precondition(Inbox(file: file).entries.map(\.title) == ["First", "Second"])

        let legacy = Data(#"[{"id":"FEF23C84-C147-4BCA-9BB3-22F3987DDE90","title":"Old","site":"example.org","category":"Почитать","createdAt":1,"status":"inbox"}]"#.utf8)
        try legacy.write(to: file, options: .atomic)
        let migrated = Inbox(file: file)
        precondition(migrated.entries.first?.category == .read)
        precondition(migrated.entries.first?.titleWasEdited == false)

        let bad = Data("corrupt inbox".utf8)
        try bad.write(to: file, options: .atomic)
        let corrupt = Inbox(file: file)
        guard case .failed = corrupt.add("Keep the original", category: nil) else {
            preconditionFailure("Corrupt data was overwritten")
        }
        let preserved = try Data(contentsOf: file)
        precondition(preserved == bad && corrupt.error != nil)
        let link = file.deletingLastPathComponent().appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(Inbox(file: link).error != nil)

        let duplicatesFile = root.appendingPathComponent("EditDuplicates/inbox.json")
        let store = InboxStore(file: duplicatesFile)
        let video = Entry(title: "Existing video", url: URL(string: "https://youtu.be/jNQXAC9IVRw"))
        let note = Entry(title: "Edit me")
        _ = try store.write([video, note], replacing: nil)
        let duplicates = Inbox(file: duplicatesFile)
        var edited = note
        edited.url = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        precondition(!duplicates.edit(edited, originalTitle: note.title))
        precondition(duplicates.entries.last?.url == nil)
    }

    @MainActor
    private static func checkCapture() {
        func capture(_ string: String) -> String? { URL(string: string).flatMap(CaptureInput.fromURL) }
        precondition(capture("tucknote://capture?text=Hello%20%26%20world") == "Hello & world")
        precondition(capture("tucknote://capture?text=%F0%9F%93%9D") == "📝")
        precondition(capture("tucknote://capture?text=One&text=Two") == nil)
        precondition(capture("tucknote://capture?text=%00") == nil)
        precondition(capture("tucknote://other?text=Hello") == nil)
        precondition(CaptureInput.validate(String(repeating: "x", count: 32769)) == nil)

        let draft = CaptureDraft()
        draft.input = "Unsaved draft"
        precondition(draft.receive("First imported draft"))
        precondition(draft.receive("Second imported draft"))
        precondition(draft.receive("Second imported draft"))
        precondition(draft.input == "Unsaved draft" && draft.waitingCount == 2)
        draft.clearAndAdvance()
        precondition(draft.input == "First imported draft" && draft.waitingCount == 1)
        draft.clearAndAdvance()
        precondition(draft.input == "Second imported draft" && draft.waitingCount == 0)
    }

    private static func checkUpdates() throws {
        let app = Data(#"{"tag_name":"v1.10","draft":false,"prerelease":false,"assets":[{"name":"Tucknote-1.10-macos-arm64.zip","state":"uploaded","size":42}]}"#.utf8)
        let source = Data(#"{"tag_name":"v1.10","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        let preview = Data(#"{"tag_name":"v1.10","draft":false,"prerelease":true,"assets":[]}"#.utf8)
        let page = URL(string: "https://github.com/Scheegl/tucknote/releases/tag/v1.10")!
        let checks: [(Int, Data, String, Updates.Result)] = [
            (404, Data(), "1.9", .noRelease),
            (200, app, "1.9", .newer(version: "1.10", page: page, appAvailable: true)),
            (200, source, "1.9", .newer(version: "1.10", page: page, appAvailable: false)),
            (200, app, "1.10.0", .upToDate),
            (200, app, "2.0", .upToDate),
            (200, preview, "1.9", .noRelease)
        ]
        for (status, data, current, expected) in checks {
            let result = try Updates.result(status: status, data: data, current: current)
            precondition(result == expected)
        }
        do {
            _ = try Updates.result(status: 403, data: Data(), current: "1.9")
            preconditionFailure("A rate limit was treated as no update")
        } catch Updates.Failure.invalidResponse {}
    }
}
