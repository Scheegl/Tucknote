import Foundation

enum AppVersion {
    static let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
}

enum Updates {
    static let repository = URL(string: "https://github.com/Scheegl/tucknote")!
    private static let endpoint = URL(string: "https://api.github.com/repos/Scheegl/tucknote/releases/latest")!

    enum Result: Equatable {
        case noRelease
        case upToDate
        case newer(version: String, page: URL, appAvailable: Bool)
    }

    enum Failure: Error {
        case invalidResponse
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
        }

        let tag: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name", draft, prerelease, assets
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func check(current: String) async throws -> Result {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.invalidResponse }
        return try result(status: status, data: data, current: current)
    }

    static func result(status: Int, data: Data, current: String) throws -> Result {
        if status == 404 { return .noRelease }
        guard status == 200, let installed = components(from: current) else { throw Failure.invalidResponse }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return .noRelease }

        let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        guard let latest = components(from: version) else { throw Failure.invalidResponse }
        guard installed.lexicographicallyPrecedes(latest) else { return .upToDate }

        let assetName = "Tucknote-\(version)-macos-arm64.zip"
        let available = release.assets.contains { $0.name == assetName && $0.state == "uploaded" && $0.size > 0 }
        let page = repository.appendingPathComponent("releases").appendingPathComponent("tag")
            .appendingPathComponent(release.tag)
        return .newer(version: version, page: page, appAvailable: available)
    }

    private static func components(from value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}
