import Foundation

public enum SwitchTransactionState: String, Codable, Equatable {
    case idle
    case locked
    case baselineCaptured
    case targetValidated
    case backupCreated
    case authReplaced
    case sharedStateVerified
    case restartRequested
    case succeeded
    case failedBeforeReplace
    case rolledBack
    case rollbackFailed
    case restartFailedAfterSafeSwitch
}

public struct SwitchTransactionResult: Equatable {
    public let profileId: UUID
    public let state: SwitchTransactionState
    public let rollbackSucceeded: Bool
    public let restartSucceeded: Bool?
    public let message: String?
}

public protocol CodexLaunching {
    func gracefulRestart() throws
}

public struct NoopCodexLauncher: CodexLaunching {
    public init() {}
    public func gracefulRestart() throws {}
}

public final class ProfileSwitchService {
    private let store: ProfileStore
    private let verifier: SharedStateVerifying
    private let transaction: AuthFileTransaction
    private let launcher: CodexLaunching
    private let lock = NSLock()

    public init(store: ProfileStore, verifier: SharedStateVerifying, transaction: AuthFileTransaction, launcher: CodexLaunching) {
        self.store = store
        self.verifier = verifier
        self.transaction = transaction
        self.launcher = launcher
    }

    public func switchProfile(id: UUID) throws -> SwitchTransactionResult {
        lock.lock()
        defer { lock.unlock() }

        let baseline = try verifier.capture()
        let profile = try store.profile(id: id)
        let snapshot = try store.snapshotURL(for: profile)
        var handle: AuthRollbackHandle?
        do {
            handle = try transaction.replaceActiveAuth(with: snapshot)
            let verification = try verifier.verify(against: baseline)
            guard verification.isValid else {
                if let handle {
                    try transaction.rollback(handle)
                }
                return SwitchTransactionResult(profileId: id, state: .rolledBack, rollbackSucceeded: true, restartSucceeded: nil, message: "shared state changed")
            }

            try store.updateLastUsed(profileId: id)
            do {
                try launcher.gracefulRestart()
                return SwitchTransactionResult(profileId: id, state: .succeeded, rollbackSucceeded: false, restartSucceeded: true, message: nil)
            } catch {
                return SwitchTransactionResult(profileId: id, state: .restartFailedAfterSafeSwitch, rollbackSucceeded: false, restartSucceeded: false, message: "restart failed")
            }
        } catch {
            if let handle {
                do {
                    try transaction.rollback(handle)
                    return SwitchTransactionResult(profileId: id, state: .rolledBack, rollbackSucceeded: true, restartSucceeded: nil, message: "switch failed")
                } catch {
                    return SwitchTransactionResult(profileId: id, state: .rollbackFailed, rollbackSucceeded: false, restartSucceeded: nil, message: "rollback failed")
                }
            }
            return SwitchTransactionResult(profileId: id, state: .failedBeforeReplace, rollbackSucceeded: false, restartSucceeded: nil, message: "switch failed before replace")
        }
    }
}
