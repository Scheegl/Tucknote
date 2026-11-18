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
        print("Tucknote checks passed")
    }
}
