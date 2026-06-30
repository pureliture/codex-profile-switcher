import Foundation

public enum CodexProfileSwitcherError: Error, CustomStringConvertible, Equatable {
    case invalidAuthJSON
    case unsafePath(String)
    case missingActiveAuth
    case backupUnavailable
    case sharedStateChanged([SharedStateViolation])
    case loginCancelled
    case loginFailed
    case loginDidNotCreateAuth
    case realCodexHomeChanged
    case profileNotFound
    case rollbackUnavailable
    case activeProfileRemovalBlocked

    public var description: String {
        switch self {
        case .invalidAuthJSON:
            return "invalid auth JSON"
        case .unsafePath(let reason):
            return "unsafe path: \(reason)"
        case .missingActiveAuth:
            return "missing active auth"
        case .backupUnavailable:
            return "backup unavailable"
        case .sharedStateChanged:
            return "shared state changed"
        case .loginCancelled:
            return "login cancelled"
        case .loginFailed:
            return "login failed"
        case .loginDidNotCreateAuth:
            return "login did not create auth"
        case .realCodexHomeChanged:
            return "real Codex home changed during login"
        case .profileNotFound:
            return "profile not found"
        case .rollbackUnavailable:
            return "rollback unavailable"
        case .activeProfileRemovalBlocked:
            return "active profile removal blocked"
        }
    }
}

public struct Profile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var label: String
    public var email: String?
    public var snapshotRelativePath: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID,
        label: String,
        email: String?,
        snapshotRelativePath: String,
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date?
    ) {
        self.id = id
        self.label = label
        self.email = email
        self.snapshotRelativePath = snapshotRelativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct ProfileRegistry: Codable, Equatable {
    public var schemaVersion: Int
    public var activeProfileId: UUID?
    public var profiles: [Profile]

    public init(schemaVersion: Int = 1, activeProfileId: UUID? = nil, profiles: [Profile] = []) {
        self.schemaVersion = schemaVersion
        self.activeProfileId = activeProfileId
        self.profiles = profiles
    }
}

public struct ProfileSummary: Equatable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let label: String
    public let email: String?
    public let isActive: Bool

    public init(id: UUID, label: String, email: String?, isActive: Bool) {
        self.id = id
        self.label = label
        self.email = email
        self.isActive = isActive
    }

    public var description: String {
        "ProfileSummary(id: \(id.uuidString), label: \(label), email: \(email ?? "nil"), isActive: \(isActive))"
    }
}

public enum PanelStatus: Equatable, CustomStringConvertible {
    case idle
    case switching
    case error(String)

    public var description: String {
        switch self {
        case .idle: return "idle"
        case .switching: return "switching"
        case .error(let message): return "error(\(message))"
        }
    }
}

public struct PanelState: Equatable, CustomStringConvertible {
    public let profiles: [ProfileSummary]
    public let status: PanelStatus

    public init(profiles: [ProfileSummary], status: PanelStatus) {
        self.profiles = profiles
        self.status = status
    }

    public var description: String {
        "PanelState(profiles: \(profiles), status: \(status))"
    }
}

public enum ProfilePanelAction: String, CaseIterable, Equatable {
    case addProfile
    case switchProfile
    case renameLabel
    case removeProfile
    case refreshLocalProfiles
    case openSettings
    case quitApp
}
