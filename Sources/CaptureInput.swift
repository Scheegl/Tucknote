import Foundation

enum CaptureInput {
    static func validate(_ input: String) -> String? {
        guard input.utf8.count <= 32 * 1024, !input.utf8.contains(0) else { return nil }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func fromURL(_ url: URL) -> String? {
        guard url.absoluteString.utf8.count <= 100 * 1024,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "tucknote", parts.host?.lowercased() == "capture",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "text", let text = items[0].value else { return nil }
        return validate(text)
    }
}
