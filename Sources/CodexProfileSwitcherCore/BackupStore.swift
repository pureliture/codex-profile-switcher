import Foundation

public final class BackupStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func createBackup(from data: Data, date: Date = Date()) throws -> URL {
        try FileSecurity.ensureDirectory(root)
        try FileSecurity.validateJSONAuth(data)
        let timestamp = Int(date.timeIntervalSince1970)
        let url = root.appendingPathComponent("auth.\(timestamp).\(UUID().uuidString).json")
        try data.write(to: url, options: [])
        try FileSecurity.setPermissions(0o600, for: url)
        try FileSecurity.validateTokenFile(url)
        return url
    }

    public func restore(from backupURL: URL, to activeAuthURL: URL) throws {
        try FileSecurity.validateTokenFile(backupURL)
        let backupData = try Data(contentsOf: backupURL)
        try FileSecurity.atomicWrite(backupData, to: activeAuthURL)
    }

    public func prune(retainLatest: Int = 10, olderThan: TimeInterval = 60 * 60 * 24 * 30, now: Date = Date()) throws {
        guard retainLatest > 0 else { return }
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let backups = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )
        .filter { $0.lastPathComponent.hasPrefix("auth.") && $0.lastPathComponent.hasSuffix(".json") }
        .compactMap { url -> BackupRecord? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return BackupRecord(url: url, modified: modified)
        }
        .sorted {
            if $0.modified == $1.modified {
                return $0.url.path > $1.url.path
            }
            return $0.modified > $1.modified
        }

        guard backups.count > 1 else { return }
        for (index, record) in backups.enumerated() {
            if index == 0 {
                continue
            }
            let isBeyondRetainedSet = index >= retainLatest
            let isTooOld = now.timeIntervalSince(record.modified) > olderThan
            if isBeyondRetainedSet || isTooOld {
                try? FileManager.default.removeItem(at: record.url)
            }
        }
    }
}

private struct BackupRecord {
    let url: URL
    let modified: Date
}
