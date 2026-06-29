import Foundation

public struct AuthRollbackHandle: Equatable {
    public let backupURL: URL
    public let activeAuthURL: URL
}

public final class AuthFileTransaction {
    private let codexHome: URL
    private let backupStore: BackupStore
    private var activeAuthURL: URL { codexHome.appendingPathComponent("auth.json") }

    public init(codexHome: URL, backupRoot: URL) {
        self.codexHome = codexHome
        self.backupStore = BackupStore(root: backupRoot)
    }

    public func replaceActiveAuth(with profileAuthURL: URL) throws -> AuthRollbackHandle {
        try FileSecurity.validateTokenFile(profileAuthURL)
        let replacementData = try Data(contentsOf: profileAuthURL)
        try FileSecurity.validateJSONAuth(replacementData)
        try FileSecurity.validateTokenFile(activeAuthURL)
        let currentData = try Data(contentsOf: activeAuthURL)
        try FileSecurity.validateJSONAuth(currentData)

        let backupURL = try backupStore.createBackup(from: currentData)

        try FileSecurity.atomicWrite(replacementData, to: activeAuthURL)
        try? backupStore.prune()
        return AuthRollbackHandle(backupURL: backupURL, activeAuthURL: activeAuthURL)
    }

    public func rollback(_ handle: AuthRollbackHandle) throws {
        try backupStore.restore(from: handle.backupURL, to: handle.activeAuthURL)
    }
}
