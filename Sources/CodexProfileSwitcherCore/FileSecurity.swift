import Darwin
import Foundation

enum FileSecurity {
    static func ensureDirectory(_ url: URL, permissions: Int = 0o700) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    static func setPermissions(_ permissions: Int, for url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    static func validateTokenFile(_ url: URL, mustExist: Bool = true) throws {
        var statBuffer = stat()
        let status = lstat(url.path, &statBuffer)
        if status != 0 {
            if mustExist && errno == ENOENT {
                throw CodexProfileSwitcherError.missingActiveAuth
            }
            if !mustExist {
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let type = statBuffer.st_mode & S_IFMT
        if type == S_IFLNK {
            throw CodexProfileSwitcherError.unsafePath("symlink token path rejected")
        }
        if type != S_IFREG {
            throw CodexProfileSwitcherError.unsafePath("token path is not a regular file")
        }
        if statBuffer.st_nlink > 1 {
            throw CodexProfileSwitcherError.unsafePath("hardlinked token path rejected")
        }
        if statBuffer.st_uid != getuid() {
            throw CodexProfileSwitcherError.unsafePath("token path owner mismatch")
        }
    }

    static func validateParentDirectory(_ url: URL) throws {
        var statBuffer = stat()
        guard lstat(url.deletingLastPathComponent().path, &statBuffer) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if statBuffer.st_uid != getuid() {
            throw CodexProfileSwitcherError.unsafePath("parent directory owner mismatch")
        }
    }

    static func validateJSONAuth(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CodexProfileSwitcherError.invalidAuthJSON
        }

        if let tokens = dictionary["tokens"] as? [String: Any],
           tokens["access_token"] is String || tokens["refresh_token"] is String {
            return
        }

        throw CodexProfileSwitcherError.invalidAuthJSON
    }

    static func atomicWrite(_ data: Data, to destination: URL, permissions: Int = 0o600) throws {
        try validateParentDirectory(destination)
        try ensureDirectory(destination.deletingLastPathComponent())
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp.\(UUID().uuidString)")
        try data.write(to: temporary, options: [])
        try setPermissions(permissions, for: temporary)
        try validateJSONAuth(data)

        if rename(temporary.path, destination.path) != 0 {
            try? FileManager.default.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try setPermissions(permissions, for: destination)
        try validateTokenFile(destination)
        try validateJSONAuth(Data(contentsOf: destination))
    }
}

func stableHash(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return String(format: "%016llx", hash)
}
