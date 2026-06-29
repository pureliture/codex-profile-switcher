import Foundation

public struct RedactedAuditEvent: Codable, Equatable {
    public let timestamp: Date
    public let operation: String
    public let profileId: UUID?
    public let state: String
    public let result: String

    public init(timestamp: Date = Date(), operation: String, profileId: UUID?, state: String, result: String) {
        self.timestamp = timestamp
        self.operation = operation
        self.profileId = profileId
        self.state = state
        self.result = result
    }
}

public final class RedactedAuditLog {
    private let url: URL
    private let encoder = JSONEncoder()

    public init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(_ event: RedactedAuditEvent) throws {
        try validateRedacted(event)
        try FileSecurity.ensureDirectory(url.deletingLastPathComponent())
        let data = try encoder.encode(event)
        let line = String(data: data, encoding: .utf8)! + "\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            try FileSecurity.setPermissions(0o600, for: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    }

    private func validateRedacted(_ event: RedactedAuditEvent) throws {
        let searchable = [
            event.operation,
            event.state,
            event.result
        ].joined(separator: "\n").lowercased()
        let forbidden = [
            "access_token",
            "refresh_token",
            "id_token",
            "authorization",
            "bearer "
        ]
        if forbidden.contains(where: { searchable.contains($0) }) {
            throw CodexProfileSwitcherError.unsafePath("audit event contains token-like material")
        }
    }
}
