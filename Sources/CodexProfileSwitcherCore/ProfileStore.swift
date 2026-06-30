import Foundation

public final class ProfileStore {
    public let appStateRoot: URL
    private let registryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(appStateRoot: URL) {
        self.appStateRoot = appStateRoot
        self.registryURL = appStateRoot.appendingPathComponent("registry.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func initialize() throws {
        try FileSecurity.ensureDirectory(appStateRoot)
        try FileSecurity.ensureDirectory(appStateRoot.appendingPathComponent("profiles"))
    }

    public func createProfile(label: String, email: String?, authJSON: Data) throws -> Profile {
        try FileSecurity.validateJSONAuth(authJSON)
        try initialize()
        var registry = (try? loadRegistry()) ?? ProfileRegistry()
        let id = UUID()
        let now = Date()
        let relativePath = "profiles/\(id.uuidString)/auth.json"
        let profileDirectory = appStateRoot.appendingPathComponent("profiles").appendingPathComponent(id.uuidString)
        try FileSecurity.ensureDirectory(profileDirectory)
        let snapshot = profileDirectory.appendingPathComponent("auth.json")
        try authJSON.write(to: snapshot, options: [])
        try FileSecurity.setPermissions(0o600, for: snapshot)
        try FileSecurity.validateTokenFile(snapshot)
        let profile = Profile(
            id: id,
            label: label,
            email: email,
            snapshotRelativePath: relativePath,
            createdAt: now,
            updatedAt: now,
            lastUsedAt: nil
        )
        registry.profiles.append(profile)
        try saveRegistry(registry)
        return profile
    }

    public func loadRegistry() throws -> ProfileRegistry {
        let data = try Data(contentsOf: registryURL)
        return try decoder.decode(ProfileRegistry.self, from: data)
    }

    public func saveRegistry(_ registry: ProfileRegistry) throws {
        try initialize()
        let data = try encoder.encode(registry)
        try data.write(to: registryURL, options: [])
        try FileSecurity.setPermissions(0o600, for: registryURL)
    }

    public func snapshotURL(for profile: Profile) throws -> URL {
        guard !profile.snapshotRelativePath.contains(".."),
              !profile.snapshotRelativePath.hasPrefix("/") else {
            throw CodexProfileSwitcherError.unsafePath("snapshot path escapes app root")
        }
        let url = appStateRoot.appendingPathComponent(profile.snapshotRelativePath)
        let standardizedRoot = appStateRoot.standardizedFileURL.path
        let standardizedSnapshot = url.standardizedFileURL.path
        guard standardizedSnapshot.hasPrefix(standardizedRoot + "/") else {
            throw CodexProfileSwitcherError.unsafePath("snapshot path escapes app root")
        }
        return url
    }

    public func profile(id: UUID) throws -> Profile {
        guard let profile = try loadRegistry().profiles.first(where: { $0.id == id }) else {
            throw CodexProfileSwitcherError.profileNotFound
        }
        return profile
    }

    public func updateLastUsed(profileId: UUID) throws {
        var registry = try loadRegistry()
        guard let index = registry.profiles.firstIndex(where: { $0.id == profileId }) else {
            throw CodexProfileSwitcherError.profileNotFound
        }
        registry.activeProfileId = profileId
        registry.profiles[index].lastUsedAt = Date()
        registry.profiles[index].updatedAt = Date()
        try saveRegistry(registry)
    }

    public func removeProfile(id: UUID) throws {
        var registry = try loadRegistry()
        guard let index = registry.profiles.firstIndex(where: { $0.id == id }) else {
            throw CodexProfileSwitcherError.profileNotFound
        }
        guard registry.activeProfileId != id else {
            throw CodexProfileSwitcherError.activeProfileRemovalBlocked
        }

        let profile = registry.profiles[index]
        let snapshot = try snapshotURL(for: profile)
        let profileDirectory = snapshot.deletingLastPathComponent()
        guard profileDirectory.deletingLastPathComponent().lastPathComponent == "profiles",
              profileDirectory.lastPathComponent == id.uuidString else {
            throw CodexProfileSwitcherError.unsafePath("profile directory must match profile UUID")
        }

        let removalRoot = appStateRoot.appendingPathComponent("removed")
        let tombstone = removalRoot.appendingPathComponent("\(id.uuidString)-\(UUID().uuidString)")
        var movedSnapshot = false
        if FileManager.default.fileExists(atPath: profileDirectory.path) {
            try FileSecurity.ensureDirectory(removalRoot)
            try FileManager.default.moveItem(at: profileDirectory, to: tombstone)
            movedSnapshot = true
        }

        do {
            registry.profiles.remove(at: index)
            try saveRegistry(registry)
            if movedSnapshot {
                try? FileManager.default.removeItem(at: tombstone)
            }
        } catch {
            if movedSnapshot && !FileManager.default.fileExists(atPath: profileDirectory.path) {
                try? FileManager.default.moveItem(at: tombstone, to: profileDirectory)
            }
            throw error
        }
    }
}
