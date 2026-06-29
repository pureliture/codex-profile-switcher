import Foundation

public enum SharedStateViolationCategory: String, Codable, Equatable {
    case strongFileChanged
    case lightweightFingerprintChanged
}

public struct SharedStateViolation: Codable, Equatable {
    public let category: SharedStateViolationCategory
    public let path: String
}

public struct SharedStateVerificationResult: Equatable {
    public let violations: [SharedStateViolation]
    public var isValid: Bool { violations.isEmpty }
}

public struct SharedStateBaseline: Equatable {
    fileprivate let strong: [String: String]
    fileprivate let light: [String: LightweightFingerprint]
}

public protocol SharedStateVerifying {
    func capture() throws -> SharedStateBaseline
    func verify(against baseline: SharedStateBaseline) throws -> SharedStateVerificationResult
}

struct LightweightFingerprint: Equatable {
    let pathSetHash: String
    let fileCount: Int
    let directoryCount: Int
    let totalBytes: UInt64
    let maxModifiedTimeBucket: Int
}

public final class SharedStateVerifier: SharedStateVerifying {
    private let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    public func capture() throws -> SharedStateBaseline {
        SharedStateBaseline(strong: try strongFingerprints(), light: try lightFingerprints())
    }

    public func verify(against baseline: SharedStateBaseline) throws -> SharedStateVerificationResult {
        let currentStrong = try strongFingerprints()
        let currentLight = try lightFingerprints()
        var violations: [SharedStateViolation] = []

        for key in Set(baseline.strong.keys).union(currentStrong.keys).sorted() where baseline.strong[key] != currentStrong[key] {
            violations.append(SharedStateViolation(category: .strongFileChanged, path: key))
        }

        for key in Set(baseline.light.keys).union(currentLight.keys).sorted() where baseline.light[key] != currentLight[key] {
            violations.append(SharedStateViolation(category: .lightweightFingerprintChanged, path: key))
        }

        return SharedStateVerificationResult(violations: violations)
    }

    private func strongFingerprints() throws -> [String: String] {
        var result: [String: String] = [:]
        let direct = ["config.toml", "settings.json"]
        for path in direct {
            let url = codexHome.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                result[path] = stableHash(try Data(contentsOf: url))
            }
        }

        for rootName in ["skills", "plugins"] {
            let root = codexHome.appendingPathComponent(rootName)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let files = try regularFiles(under: root)
                .filter { !$0.path.contains("/cache/") && !$0.lastPathComponent.hasSuffix(".zip") }
            for file in files {
                let key = "\(rootName)/\(relativePath(file, from: root))"
                result[key] = stableHash(try Data(contentsOf: file))
            }
        }

        let rootItems = (try? FileManager.default.contentsOfDirectory(at: codexHome, includingPropertiesForKeys: nil)) ?? []
        for item in rootItems where item.lastPathComponent.hasPrefix("mcp") {
            if isDirectory(item) {
                for file in try regularFiles(under: item) {
                    let key = "\(item.lastPathComponent)/\(relativePath(file, from: item))"
                    result[key] = stableHash(try Data(contentsOf: file))
                }
            } else {
                result[item.lastPathComponent] = stableHash(try Data(contentsOf: item))
            }
        }

        return result
    }

    private func lightFingerprints() throws -> [String: LightweightFingerprint] {
        var result: [String: LightweightFingerprint] = [:]
        for name in ["sessions", "log", "history", "rollouts"] {
            let url = codexHome.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                result[name] = try lightweightFingerprint(for: url)
            }
        }
        return result
    }

    private func lightweightFingerprint(for root: URL) throws -> LightweightFingerprint {
        var paths: [String] = []
        var fileCount = 0
        var directoryCount = 0
        var totalBytes: UInt64 = 0
        var maxMtime: TimeInterval = 0
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            paths.append(relativePath(url, from: root))
            if values.isDirectory == true { directoryCount += 1 }
            if values.isRegularFile == true {
                fileCount += 1
                totalBytes += UInt64(values.fileSize ?? 0)
            }
            maxMtime = max(maxMtime, values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
        return LightweightFingerprint(
            pathSetHash: stableHash(Data(paths.sorted().joined(separator: "\n").utf8)),
            fileCount: fileCount,
            directoryCount: directoryCount,
            totalBytes: totalBytes,
            maxModifiedTimeBucket: Int(maxMtime / 5.0)
        )
    }

    private func regularFiles(under root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    private func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
