import CryptoKit
import Darwin
import Foundation

struct InboxStore {
    struct Snapshot {
        let entries: [Entry]
        let revision: SHA256.Digest?
    }

    enum Failure: LocalizedError {
        case invalidFile
        case invalidEntries
        case changed(Snapshot)

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "The inbox must be a regular file in its own directory."
            case .invalidEntries: return "The inbox contains duplicate entry identifiers."
            case .changed: return "Another Tucknote window or process changed the inbox. The list was reloaded. Try your action again."
            }
        }
    }

    let file: URL
    private let manager = FileManager.default

    func read() throws -> Snapshot {
        do {
            let attributes = try manager.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.invalidFile }
            let data = try Data(contentsOf: file)
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            guard Set(entries.map(\.id)).count == entries.count else { throw Failure.invalidEntries }
            return Snapshot(entries: entries, revision: SHA256.hash(data: data))
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return Snapshot(entries: [], revision: nil)
        }
    }

    func write(_ entries: [Entry], replacing revision: SHA256.Digest?) throws -> Snapshot {
        let directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.invalidFile }
        if attributes[.posixPermissions] as? Int != 0o700 {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        let lock = directory.appendingPathComponent(".inbox.lock")
        let descriptor = open(lock.path, O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.invalidFile }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw posixError() }

        let current = try read()
        guard current.revision == revision else { throw Failure.changed(current) }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: file, options: .atomic)
        return Snapshot(entries: entries, revision: SHA256.hash(data: data))
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
