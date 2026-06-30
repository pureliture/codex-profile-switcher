import Foundation
import CodexProfileSwitcherCore

@main
struct CoreTestRunner {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("ProfileStore stores snapshots under UUID paths", testCreateProfileStoresSnapshotUnderUUIDPathAndRegistryMetadata),
            ("ProfileStore removes inactive profile snapshots", testRemoveInactiveProfileDeletesSnapshotAndRegistryEntry),
            ("ProfileStore blocks active profile removal", testRemoveActiveProfileIsBlocked),
            ("ProfileStore rejects invalid auth JSON", testRejectsInvalidAuthJSONBeforeCreatingProfile),
            ("ProfileStore rejects API-key auth JSON", testRejectsAPIKeyAuthJSONBeforeCreatingProfile),
            ("AuthFileTransaction replaces, backs up, and rolls back", testReplaceBacksUpActiveAuthAndCanRollback),
            ("AuthFileTransaction rejects symlink snapshots", testRejectsSymlinkProfileSnapshot),
            ("BackupStore prunes old backups while retaining latest", testBackupStorePrunesOldBackups),
            ("SharedStateVerifier allows auth-only changes", testAuthChangeOnlyPassesVerification),
            ("SharedStateVerifier rejects config changes", testConfigChangeFailsStrongVerification),
            ("SharedStateVerifier rejects session fingerprint changes", testSessionFingerprintChangeFailsBeforeRestart),
            ("OfficialLoginCoordinator imports temp auth without touching real home", testSuccessfulLoginImportsTemporaryAuthWithoutTouchingRealCodexHome),
            ("OfficialLoginCoordinator creates no profile on cancel", testCancelledLoginCreatesNoProfile),
            ("OfficialLoginCoordinator purges stale temp homes", testPurgesStaleTemporaryLoginHomes),
            ("ProfileSwitchService rolls back before restart on verifier failure", testSwitchRollsBackAndDoesNotRestartWhenSharedStateChanges),
            ("ProfileSwitchService reports restart failure after safe switch", testSwitchReportsRestartFailureAfterVerifiedAuthReplace),
            ("ReleaseGate blocks public binaries and missing provenance", testReleaseGateBlocksUnsafeInternalArtifacts),
            ("RedactedAuditLog writes no token fields", testAuditLogRejectsTokenLikeFields),
            ("Panel actions contain only approved profile actions", testPanelActionsContainOnlyApprovedProfileActions),
            ("Panel state carries no token material", testPanelStateCarriesProfilesWithoutTokenMaterial)
        ]

        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL \(name): \(error)")
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) core tests passed.")
        } else {
            fputs("\(failures.count) test(s) failed.\n", stderr)
            exit(1)
        }
    }
}

func testCreateProfileStoresSnapshotUnderUUIDPathAndRegistryMetadata() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let profile = try store.createProfile(
        label: "Enterprise",
        email: "person@example.com",
        authJSON: fixture.validAuthJSON()
    )

    try expect(profile.label == "Enterprise", "label stored")
    try expect(profile.email == "person@example.com", "email metadata stored")
    try expect(!profile.snapshotRelativePath.contains("person"), "path excludes email")
    try expect(!profile.snapshotRelativePath.contains("Enterprise"), "path excludes label")
    try expect(profile.snapshotRelativePath.hasPrefix("profiles/\(profile.id.uuidString)/"), "path uses UUID")

    let snapshotURL = try store.snapshotURL(for: profile)
    try expect(FileManager.default.fileExists(atPath: snapshotURL.path), "snapshot exists")
    try expect(try fixture.posixPermissions(snapshotURL) == 0o600, "snapshot permission 0600")
    try expect(try fixture.posixPermissions(fixture.appStateRoot) == 0o700, "app root permission 0700")

    let registry = try store.loadRegistry()
    try expect(registry.schemaVersion == 1, "schema version")
    try expect(registry.profiles.map(\.id) == [profile.id], "registry contains profile")
    try expect(try fixture.posixPermissions(fixture.appStateRoot.appendingPathComponent("registry.json")) == 0o600, "registry permission 0600")
}

func testRemoveInactiveProfileDeletesSnapshotAndRegistryEntry() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let active = try store.createProfile(label: "Personal", email: nil, authJSON: fixture.validAuthJSON(accessToken: "active"))
    let inactive = try store.createProfile(label: "Enterprise", email: nil, authJSON: fixture.validAuthJSON(accessToken: "inactive"))
    try store.updateLastUsed(profileId: active.id)

    let inactiveSnapshot = try store.snapshotURL(for: inactive)
    let inactiveDirectory = inactiveSnapshot.deletingLastPathComponent()

    try store.removeProfile(id: inactive.id)

    let registry = try store.loadRegistry()
    try expect(registry.profiles.map(\.id) == [active.id], "registry removes inactive profile")
    try expect(registry.activeProfileId == active.id, "active profile remains active")
    try expect(!FileManager.default.fileExists(atPath: inactiveDirectory.path), "profile snapshot directory removed")
}

func testRemoveActiveProfileIsBlocked() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let active = try store.createProfile(label: "Personal", email: nil, authJSON: fixture.validAuthJSON(accessToken: "active"))
    try store.updateLastUsed(profileId: active.id)

    let activeSnapshot = try store.snapshotURL(for: active)

    try expectThrows("active profile removal blocked") {
        try store.removeProfile(id: active.id)
    }

    let registry = try store.loadRegistry()
    try expect(registry.profiles.map(\.id) == [active.id], "active profile remains registered")
    try expect(FileManager.default.fileExists(atPath: activeSnapshot.path), "active snapshot remains")
}

func testRejectsInvalidAuthJSONBeforeCreatingProfile() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    try expectThrows("invalid auth rejected") {
        _ = try store.createProfile(label: "Bad", email: nil, authJSON: Data("{".utf8))
    }
    try expect(!FileManager.default.fileExists(atPath: fixture.appStateRoot.appendingPathComponent("registry.json").path), "registry not created")
}

func testRejectsAPIKeyAuthJSONBeforeCreatingProfile() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    try expectThrows("API-key mode auth rejected") {
        _ = try store.createProfile(label: "API", email: nil, authJSON: Data(#"{"OPENAI_API_KEY":"sk-local"}"#.utf8))
    }
}

func testReplaceBacksUpActiveAuthAndCanRollback() throws {
    let fixture = try TempFixture()
    try fixture.write(fixture.validAuthJSON(accessToken: "old"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)
    let profileAuth = fixture.appStateRoot.appendingPathComponent("profile-auth.json")
    try fixture.write(fixture.validAuthJSON(accessToken: "new"), to: profileAuth, permissions: 0o600)

    let transaction = AuthFileTransaction(codexHome: fixture.codexHome, backupRoot: fixture.appStateRoot.appendingPathComponent("backups"))
    let handle = try transaction.replaceActiveAuth(with: profileAuth)

    try expect(String(data: try Data(contentsOf: fixture.codexHome.appendingPathComponent("auth.json")), encoding: .utf8)?.contains("new") == true, "new auth active")
    try expect(try fixture.posixPermissions(fixture.codexHome.appendingPathComponent("auth.json")) == 0o600, "active auth permission")

    try transaction.rollback(handle)
    try expect(String(data: try Data(contentsOf: fixture.codexHome.appendingPathComponent("auth.json")), encoding: .utf8)?.contains("old") == true, "rollback restored old auth")
}

func testRejectsSymlinkProfileSnapshot() throws {
    let fixture = try TempFixture()
    try fixture.write(fixture.validAuthJSON(accessToken: "old"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)
    let real = fixture.appStateRoot.appendingPathComponent("real-auth.json")
    let link = fixture.appStateRoot.appendingPathComponent("linked-auth.json")
    try fixture.write(fixture.validAuthJSON(accessToken: "new"), to: real, permissions: 0o600)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

    let transaction = AuthFileTransaction(codexHome: fixture.codexHome, backupRoot: fixture.appStateRoot.appendingPathComponent("backups"))
    try expectThrows("symlink rejected") {
        _ = try transaction.replaceActiveAuth(with: link)
    }
}

func testBackupStorePrunesOldBackups() throws {
    let fixture = try TempFixture()
    let store = BackupStore(root: fixture.appStateRoot.appendingPathComponent("backups"))
    var backups: [URL] = []
    for index in 0..<12 {
        let backup = try store.createBackup(from: fixture.validAuthJSON(accessToken: "backup-\(index)"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
            ofItemAtPath: backup.path
        )
        backups.append(backup)
    }

    try store.prune(retainLatest: 10, olderThan: 60 * 60 * 24 * 30, now: Date(timeIntervalSince1970: 60 * 60 * 24))

    let remaining = try FileManager.default.contentsOfDirectory(at: fixture.appStateRoot.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
    try expect(remaining.count == 10, "keeps latest 10 backups")
    try expect(FileManager.default.fileExists(atPath: backups.last!.path), "keeps newest backup")
    try expect(!FileManager.default.fileExists(atPath: backups.first!.path), "removes oldest backup")
}

func testAuthChangeOnlyPassesVerification() throws {
    let fixture = try TempFixture()
    try fixture.write(Data("model = \"gpt\"\n".utf8), to: fixture.codexHome.appendingPathComponent("config.toml"), permissions: 0o600)
    try fixture.write(fixture.validAuthJSON(accessToken: "old"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)

    let verifier = SharedStateVerifier(codexHome: fixture.codexHome)
    let baseline = try verifier.capture()
    try fixture.write(fixture.validAuthJSON(accessToken: "new"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)

    try expect(try verifier.verify(against: baseline).isValid, "auth-only change allowed")
}

func testConfigChangeFailsStrongVerification() throws {
    let fixture = try TempFixture()
    try fixture.write(Data("model = \"gpt\"\n".utf8), to: fixture.codexHome.appendingPathComponent("config.toml"), permissions: 0o600)

    let verifier = SharedStateVerifier(codexHome: fixture.codexHome)
    let baseline = try verifier.capture()
    try fixture.write(Data("model = \"other\"\n".utf8), to: fixture.codexHome.appendingPathComponent("config.toml"), permissions: 0o600)

    let result = try verifier.verify(against: baseline)
    try expect(!result.isValid, "config change invalid")
    try expect(result.violations.contains { $0.category == .strongFileChanged }, "strong violation recorded")
}

func testSessionFingerprintChangeFailsBeforeRestart() throws {
    let fixture = try TempFixture()
    let sessions = fixture.codexHome.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

    let verifier = SharedStateVerifier(codexHome: fixture.codexHome)
    let baseline = try verifier.capture()
    try fixture.write(Data("session".utf8), to: sessions.appendingPathComponent("one.json"), permissions: 0o600)

    let result = try verifier.verify(against: baseline)
    try expect(!result.isValid, "session fingerprint invalid")
    try expect(result.violations.contains { $0.category == .lightweightFingerprintChanged }, "light violation recorded")
}

func testSuccessfulLoginImportsTemporaryAuthWithoutTouchingRealCodexHome() throws {
    let fixture = try TempFixture()
    try fixture.write(fixture.validAuthJSON(accessToken: "real"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let runner = FakeLoginProcessRunner { tempHome in
        try fixture.write(fixture.validAuthJSON(accessToken: "new"), to: tempHome.appendingPathComponent("auth.json"), permissions: 0o600)
        return .succeeded
    }
    let coordinator = OfficialLoginCoordinator(appStateRoot: fixture.appStateRoot, codexHome: fixture.codexHome, store: store, runner: runner)

    let profile = try coordinator.addProfile(label: "Enterprise", email: nil)

    try expect(profile.label == "Enterprise", "profile imported")
    try expect(String(data: try Data(contentsOf: fixture.codexHome.appendingPathComponent("auth.json")), encoding: .utf8)?.contains("real") == true, "real home untouched")
    try expect(String(data: try Data(contentsOf: try store.snapshotURL(for: profile)), encoding: .utf8)?.contains("new") == true, "snapshot imported")
}

func testCancelledLoginCreatesNoProfile() throws {
    let fixture = try TempFixture()
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let runner = FakeLoginProcessRunner { _ in .cancelled }
    let coordinator = OfficialLoginCoordinator(appStateRoot: fixture.appStateRoot, codexHome: fixture.codexHome, store: store, runner: runner)

    try expectThrows("cancel throws") {
        _ = try coordinator.addProfile(label: "Cancelled", email: nil)
    }
    try expectThrows("no registry created") {
        _ = try store.loadRegistry()
    }
}

func testPanelActionsContainOnlyApprovedProfileActions() throws {
    let forbiddenFragments = ["usage", "reset", "api", "auto", "update", "config", "codexAuth"]
    let actionNames = ProfilePanelAction.allCases.map(\.rawValue)

    for fragment in forbiddenFragments {
        try expect(!actionNames.contains { $0.localizedCaseInsensitiveContains(fragment) }, "forbidden action fragment \(fragment)")
    }
}

func testPurgesStaleTemporaryLoginHomes() throws {
    let fixture = try TempFixture()
    let stale = fixture.appStateRoot.appendingPathComponent("tmp-login").appendingPathComponent("stale")
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
    try fixture.write(fixture.validAuthJSON(), to: stale.appendingPathComponent("auth.json"), permissions: 0o600)

    try OfficialLoginCoordinator.purgeStaleTemporaryLoginHomes(appStateRoot: fixture.appStateRoot)

    try expect(!FileManager.default.fileExists(atPath: fixture.appStateRoot.appendingPathComponent("tmp-login").path), "stale temp login root removed")
}

func testSwitchRollsBackAndDoesNotRestartWhenSharedStateChanges() throws {
    let fixture = try TempFixture()
    try fixture.write(fixture.validAuthJSON(accessToken: "old"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)
    try fixture.write(Data("model = \"gpt\"\n".utf8), to: fixture.codexHome.appendingPathComponent("config.toml"), permissions: 0o600)
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let profile = try store.createProfile(label: "Enterprise", email: nil, authJSON: fixture.validAuthJSON(accessToken: "new"))
    let verifier = MutatingVerifier(codexHome: fixture.codexHome) {
        try fixture.write(Data("model = \"changed\"\n".utf8), to: fixture.codexHome.appendingPathComponent("config.toml"), permissions: 0o600)
    }
    let launcher = RecordingLauncher()
    let service = ProfileSwitchService(
        store: store,
        verifier: verifier,
        transaction: AuthFileTransaction(codexHome: fixture.codexHome, backupRoot: fixture.appStateRoot.appendingPathComponent("backups")),
        launcher: launcher
    )

    let result = try service.switchProfile(id: profile.id)

    try expect(result.state == .rolledBack, "shared-state failure rolls back")
    try expect(result.rollbackSucceeded, "rollback flag")
    try expect(!launcher.didRestart, "restart not requested after failed verification")
    try expect(String(data: try Data(contentsOf: fixture.codexHome.appendingPathComponent("auth.json")), encoding: .utf8)?.contains("old") == true, "old auth restored")
}

func testSwitchReportsRestartFailureAfterVerifiedAuthReplace() throws {
    let fixture = try TempFixture()
    try fixture.write(fixture.validAuthJSON(accessToken: "old"), to: fixture.codexHome.appendingPathComponent("auth.json"), permissions: 0o600)
    let store = ProfileStore(appStateRoot: fixture.appStateRoot)
    let profile = try store.createProfile(label: "Enterprise", email: nil, authJSON: fixture.validAuthJSON(accessToken: "new"))
    let launcher = RecordingLauncher(error: TestFailure(description: "restart failed"))
    let service = ProfileSwitchService(
        store: store,
        verifier: SharedStateVerifier(codexHome: fixture.codexHome),
        transaction: AuthFileTransaction(codexHome: fixture.codexHome, backupRoot: fixture.appStateRoot.appendingPathComponent("backups")),
        launcher: launcher
    )

    let result = try service.switchProfile(id: profile.id)

    try expect(result.state == .restartFailedAfterSafeSwitch, "restart failure is distinct")
    try expect(result.restartSucceeded == false, "restart failure surfaced")
    try expect(String(data: try Data(contentsOf: fixture.codexHome.appendingPathComponent("auth.json")), encoding: .utf8)?.contains("new") == true, "verified switch remains active")
}

func testReleaseGateBlocksUnsafeInternalArtifacts() throws {
    let safe = ReleaseCandidate(
        commitSHA: String(repeating: "a", count: 40),
        includesMITLicense: true,
        includesUpstreamAttribution: true,
        signingIdentitySummary: "Developer ID Application: Example Team",
        notarizationProofPath: "notary/proof.json",
        checksum: String(repeating: "b", count: 64),
        publishesPublicBinary: false,
        pullRequestBuildHasCISecrets: false
    )

    try expect(ReleaseGate().evaluate(safe).isAllowed, "safe candidate allowed")

    var unsafe = safe
    unsafe.publishesPublicBinary = true
    unsafe.notarizationProofPath = nil
    let result = ReleaseGate().evaluate(unsafe)

    try expect(!result.isAllowed, "unsafe candidate blocked")
    try expect(result.failures.contains(.publicBinaryRelease), "public binary failure")
    try expect(result.failures.contains(.missingNotarizationProof), "notarization failure")
}

func testAuditLogRejectsTokenLikeFields() throws {
    let fixture = try TempFixture()
    let audit = RedactedAuditLog(url: fixture.appStateRoot.appendingPathComponent("audit.jsonl"))

    try expectThrows("token-like audit field rejected") {
        try audit.append(RedactedAuditEvent(operation: "switch", profileId: UUID(), state: "authReplaced", result: "access_token"))
    }

    try audit.append(RedactedAuditEvent(operation: "switch", profileId: UUID(), state: "succeeded", result: "ok"))
    let text = try String(contentsOf: fixture.appStateRoot.appendingPathComponent("audit.jsonl"), encoding: .utf8)
    try expect(!text.contains("access_token"), "audit excludes token field name")
}

func testPanelStateCarriesProfilesWithoutTokenMaterial() throws {
    let profile = ProfileSummary(id: UUID(), label: "Personal", email: "person@example.com", isActive: true)
    let state = PanelState(profiles: [profile], status: .idle)

    try expect(state.profiles.first?.label == "Personal", "profile label present")
    try expect(!String(describing: state).contains("access_token"), "no access token")
    try expect(!String(describing: state).contains("refresh_token"), "no refresh token")
}

struct TempFixture {
    let root: URL
    let appStateRoot: URL
    let codexHome: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-profile-switcher-tests")
            .appendingPathComponent(UUID().uuidString)
        appStateRoot = root.appendingPathComponent("app-state")
        codexHome = root.appendingPathComponent("codex-home")
        try FileManager.default.createDirectory(at: appStateRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    }

    func validAuthJSON(accessToken: String = "access") -> Data {
        Data("""
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(accessToken)",
            "refresh_token": "refresh",
            "account_id": "account"
          }
        }
        """.utf8)
    }

    func write(_ data: Data, to url: URL, permissions: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    func posixPermissions(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.posixPermissions] as? Int ?? -1
    }
}

struct FakeLoginProcessRunner: LoginProcessRunner {
    let body: (URL) throws -> LoginProcessResult

    func runLogin(temporaryCodexHome: URL, mode: LoginLaunchMode) throws -> LoginProcessResult {
        try body(temporaryCodexHome)
    }
}

final class MutatingVerifier: SharedStateVerifying {
    private let verifier: SharedStateVerifier
    private let mutateBeforeVerify: () throws -> Void

    init(codexHome: URL, mutateBeforeVerify: @escaping () throws -> Void) {
        self.verifier = SharedStateVerifier(codexHome: codexHome)
        self.mutateBeforeVerify = mutateBeforeVerify
    }

    func capture() throws -> SharedStateBaseline {
        try verifier.capture()
    }

    func verify(against baseline: SharedStateBaseline) throws -> SharedStateVerificationResult {
        try mutateBeforeVerify()
        return try verifier.verify(against: baseline)
    }
}

final class RecordingLauncher: CodexLaunching {
    private let error: Error?
    var didRestart = false

    init(error: Error? = nil) {
        self.error = error
    }

    func gracefulRestart() throws {
        didRestart = true
        if let error {
            throw error
        }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() {
        throw TestFailure(description: message)
    }
}

func expectThrows(_ message: String, _ body: () throws -> Void) throws {
    do {
        try body()
        throw TestFailure(description: "expected throw: \(message)")
    } catch is TestFailure {
        throw TestFailure(description: "expected throw: \(message)")
    } catch {
        return
    }
}
