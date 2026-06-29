import Foundation

public enum LoginLaunchMode: Equatable {
    case inApp
    case terminalFallback
}

public enum LoginProcessResult: Equatable {
    case succeeded
    case cancelled
    case failed(String)
}

public protocol LoginProcessRunner {
    func runLogin(temporaryCodexHome: URL, mode: LoginLaunchMode) throws -> LoginProcessResult
}

public final class OfficialLoginCoordinator {
    private let appStateRoot: URL
    private let codexHome: URL
    private let store: ProfileStore
    private let runner: LoginProcessRunner

    public init(appStateRoot: URL, codexHome: URL, store: ProfileStore, runner: LoginProcessRunner) {
        self.appStateRoot = appStateRoot
        self.codexHome = codexHome
        self.store = store
        self.runner = runner
    }

    public static func purgeStaleTemporaryLoginHomes(appStateRoot: URL) throws {
        let tempRoot = appStateRoot.appendingPathComponent("tmp-login")
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    public func addProfile(label: String, email: String?, mode: LoginLaunchMode = .inApp) throws -> Profile {
        let activeBefore = try activeAuthHash()
        let tempRoot = appStateRoot.appendingPathComponent("tmp-login").appendingPathComponent(UUID().uuidString)
        try FileSecurity.ensureDirectory(tempRoot)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        switch try runner.runLogin(temporaryCodexHome: tempRoot, mode: mode) {
        case .succeeded:
            break
        case .cancelled:
            throw CodexProfileSwitcherError.loginCancelled
        case .failed:
            throw CodexProfileSwitcherError.loginFailed
        }

        guard try activeAuthHash() == activeBefore else {
            throw CodexProfileSwitcherError.realCodexHomeChanged
        }

        let tempAuth = tempRoot.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: tempAuth.path) else {
            throw CodexProfileSwitcherError.loginDidNotCreateAuth
        }
        try FileSecurity.validateTokenFile(tempAuth)
        let data = try Data(contentsOf: tempAuth)
        try FileSecurity.validateJSONAuth(data)
        return try store.createProfile(label: label, email: email, authJSON: data)
    }

    private func activeAuthHash() throws -> String? {
        let active = codexHome.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: active.path) else { return nil }
        try FileSecurity.validateTokenFile(active)
        return stableHash(try Data(contentsOf: active))
    }
}

public struct DefaultLoginProcessRunner: LoginProcessRunner {
    public init() {}

    public func runLogin(temporaryCodexHome: URL, mode: LoginLaunchMode) throws -> LoginProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "login"]
        process.environment = loginEnvironment(temporaryCodexHome: temporaryCodexHome)

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        return process.terminationStatus == 0 ? .succeeded : .failed("codex login failed")
    }

    private func loginEnvironment(temporaryCodexHome: URL) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var environment: [String: String] = [
            "CODEX_HOME": temporaryCodexHome.path,
            "HOME": inherited["HOME"] ?? NSHomeDirectory(),
            "PATH": inherited["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        for key in ["SHELL", "TERM", "LANG", "LC_ALL"] {
            if let value = inherited[key] {
                environment[key] = value
            }
        }
        return environment
    }
}
