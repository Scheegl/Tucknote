import CoreFoundation
import Foundation

enum LinkMetadata {
    struct Preview: Equatable {
        let title: String?
        let description: String?
    }

    private struct Embed: Decodable { let title: String }

    static func allowsRequest(to url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" && components.host?.isEmpty == false
            && components.user == nil && components.password == nil
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let allowed = request.url.map(LinkMetadata.allowsRequest(to:)) ?? false
            completionHandler(allowed ? request : nil)
        }
    }

    static func siteTag(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("youtube.com") || host == "youtu.be" || matches("youtube-nocookie.com") { return "youtube" }
        if matches("twitter.com") || matches("x.com") { return "x.com" }
        if matches("linkedin.com") || host == "lnkd.in" { return "linkedin" }
        if matches("instagram.com") { return "instagram" }
        if matches("tiktok.com") { return "tiktok" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func needsTitle(_ title: String, for url: URL) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title.isEmpty || title == url.absoluteString.lowercased()
            || title == url.host?.lowercased() || title == siteTag(for: url)
            || (siteTag(for: url) == "x.com" && ["x", "twitter", "twitter.com"].contains(title))
            || ["sign in", "log in", "just a moment...", "access denied",
                "linkedin login, sign in", "before you continue to youtube"].contains(title)
    }

    static func canonicalYouTubeURL(for url: URL) -> URL? {
        guard siteTag(for: url) == "youtube" else { return nil }
        let path = url.path.split(separator: "/")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let host = url.host?.lowercased()
        let id: String?
        if host == "youtu.be" {
            id = path.first.map(String.init)
        } else if path.first == "watch" {
            id = query.first { $0.name == "v" }?.value
        } else if let type = path.first, ["shorts", "live", "embed", "v"].contains(type), path.count > 1 {
            id = String(path[1])
        } else {
            id = nil
        }

        var video = URLComponents()
        video.scheme = "https"
        video.host = "www.youtube.com"
        if let id, id.range(of: #"^[a-zA-Z0-9_-]{11}$"#, options: .regularExpression) != nil {
            video.path = "/watch"
            video.queryItems = [URLQueryItem(name: "v", value: id)]
        } else if path.first == "playlist",
                  let list = query.first(where: { $0.name == "list" })?.value,
                  list.range(of: #"^[a-zA-Z0-9_-]{1,128}$"#, options: .regularExpression) != nil {
            video.path = "/playlist"
            video.queryItems = [URLQueryItem(name: "list", value: list)]
        } else {
            return nil
        }
        return video.url
    }

    static func youtubeEmbedURL(for url: URL) -> URL? {
        guard let video = canonicalYouTubeURL(for: url),
              var endpoint = URLComponents(url: video, resolvingAgainstBaseURL: false) else { return nil }
        endpoint.path = "/oembed"
        endpoint.queryItems = [URLQueryItem(name: "url", value: video.absoluteString),
                               URLQueryItem(name: "format", value: "json")]
        return endpoint.url
    }

    static func title(for url: URL, allowPageFetch: Bool = true) async -> String? {
        await preview(for: url, allowPageFetch: allowPageFetch)?.title
    }

    static func preview(for url: URL, allowPageFetch: Bool = true) async -> Preview? {
        guard allowsRequest(to: url) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 9
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        if let endpoint = youtubeEmbedURL(for: url),
           let (data, _) = try? await read(session, url: endpoint, types: ["application/json"], limit: 16 * 1024),
           let embed = try? JSONDecoder().decode(Embed.self, from: data) {
            let title = normalize(embed.title)
            if !needsTitle(title, for: url) { return Preview(title: title, description: nil) }
        }
        guard allowPageFetch, !Task.isCancelled,
              let (data, response) = try? await read(session, url: url,
                  types: ["text/html", "application/xhtml+xml"], limit: 192 * 1024) else { return nil }
        let encoding = response.textEncodingName.map {
            CFStringConvertIANACharSetNameToEncoding($0 as CFString)
        } ?? kCFStringEncodingInvalidId
        let html = encoding == kCFStringEncodingInvalidId
            ? String(decoding: data, as: UTF8.self)
            : String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
                ?? String(decoding: data, as: UTF8.self)
        return htmlPreview(html, for: url)
    }

    private static func read(_ session: URLSession, url: URL, types: [String], limit: Int) async throws
        -> (Data, HTTPURLResponse)? {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              types.contains(http.mimeType ?? "") else { return nil }
        var data = Data()
        let scanHead = types.contains("text/html")
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
            if scanHead, data.count.isMultiple(of: 1024),
               String(decoding: data.suffix(1040), as: UTF8.self)
                   .range(of: "</head>", options: .caseInsensitive) != nil { break }
        }
        return (data, http)
    }

    static func htmlTitle(_ html: String, for url: URL) -> String? {
        htmlPreview(html, for: url)?.title
    }

    static func htmlPreview(_ html: String, for url: URL) -> Preview? {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
        let metaPattern = #"<meta\s+(?:"[^"]*"|'[^']*'|[^'"<>]++)*>"#
        let attributePattern = #"([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
        var metadata: [String: String] = [:]
        for tag in matches(metaPattern, in: head).compactMap({ capture($0, 0, in: head) }) {
            var attributes: [String: String] = [:]
            for match in matches(attributePattern, in: tag) {
                guard let name = capture(match, 1, in: tag)?.lowercased(),
                      let value = (2...4).compactMap({ capture(match, $0, in: tag) }).first else { continue }
                attributes[name] = value
            }
            for key in [attributes["property"], attributes["name"]].compactMap({ $0?.lowercased() }) {
                if metadata[key] == nil { metadata[key] = attributes["content"] }
            }
        }
        let pageTitle = matches(#"<title(?:\s[^>]*)?>(.*?)</title\s*>"#, in: head).first
            .flatMap { capture($0, 1, in: head) }
        let siteName = metadata["og:site_name"].map { normalize(decodeEntities($0)) }
        let isHomepage = url.path.isEmpty || url.path == "/"
        let title = [metadata["og:title"], metadata["twitter:title"], pageTitle].compactMap { $0 }
            .map { normalize(decodeEntities($0)) }.first {
                !needsTitle($0, for: url) && (isHomepage || siteName?.caseInsensitiveCompare($0) != .orderedSame)
            }
        let description = [metadata["og:description"], metadata["description"], metadata["twitter:description"]]
            .compactMap { $0 }
            .map { String(normalize(decodeEntities($0)).prefix(280)) }
            .first { !$0.isEmpty && $0 != title }
        guard title != nil || description != nil else { return nil }
        return Preview(title: title, description: description)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        return regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        Range(match.range(at: index), in: text).map { String(text[$0]) }
    }

    private static func normalize(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(600))
    }

    private static func decodeEntities(_ text: String) -> String {
        let raw = String(text.prefix(1600))
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
                        "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
                        "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"]
        var result = raw as NSString
        for match in matches(#"&(?:#x[0-9a-f]+|#[0-9]+|[a-z]+);"#, in: raw).reversed() {
            guard let entity = capture(match, 0, in: raw)?.lowercased() else { continue }
            let number = entity.hasPrefix("&#x") ? UInt32(entity.dropFirst(3).dropLast(), radix: 16)
                : entity.hasPrefix("&#") ? UInt32(entity.dropFirst(2).dropLast()) : nil
            if let replacement = entities[entity] ?? number.flatMap(Unicode.Scalar.init).map(String.init) {
                result = result.replacingCharacters(in: match.range, with: replacement) as NSString
            }
        }
        return result as String
    }
}
