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
        try checkUpdates()
        print("Tucknote checks passed")
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
