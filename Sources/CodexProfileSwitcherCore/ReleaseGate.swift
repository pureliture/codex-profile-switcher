import Foundation

public struct ReleaseCandidate: Equatable {
    public var commitSHA: String
    public var includesMITLicense: Bool
    public var includesUpstreamAttribution: Bool
    public var signingIdentitySummary: String?
    public var notarizationProofPath: String?
    public var checksum: String?
    public var publishesPublicBinary: Bool
    public var pullRequestBuildHasCISecrets: Bool

    public init(
        commitSHA: String,
        includesMITLicense: Bool,
        includesUpstreamAttribution: Bool,
        signingIdentitySummary: String?,
        notarizationProofPath: String?,
        checksum: String?,
        publishesPublicBinary: Bool,
        pullRequestBuildHasCISecrets: Bool
    ) {
        self.commitSHA = commitSHA
        self.includesMITLicense = includesMITLicense
        self.includesUpstreamAttribution = includesUpstreamAttribution
        self.signingIdentitySummary = signingIdentitySummary
        self.notarizationProofPath = notarizationProofPath
        self.checksum = checksum
        self.publishesPublicBinary = publishesPublicBinary
        self.pullRequestBuildHasCISecrets = pullRequestBuildHasCISecrets
    }
}

public enum ReleaseGateFailure: String, Codable, Equatable {
    case invalidCommitSHA
    case missingMITLicense
    case missingUpstreamAttribution
    case missingSigningIdentity
    case missingNotarizationProof
    case missingChecksum
    case publicBinaryRelease
    case pullRequestSecretsEnabled
}

public struct ReleaseGateResult: Equatable {
    public let failures: [ReleaseGateFailure]
    public var isAllowed: Bool { failures.isEmpty }
}

public struct ReleaseGate {
    public init() {}

    public func evaluate(_ candidate: ReleaseCandidate) -> ReleaseGateResult {
        var failures: [ReleaseGateFailure] = []

        if !isHex(candidate.commitSHA, length: 40) {
            failures.append(.invalidCommitSHA)
        }
        if !candidate.includesMITLicense {
            failures.append(.missingMITLicense)
        }
        if !candidate.includesUpstreamAttribution {
            failures.append(.missingUpstreamAttribution)
        }
        if candidate.signingIdentitySummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            failures.append(.missingSigningIdentity)
        }
        if candidate.notarizationProofPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            failures.append(.missingNotarizationProof)
        }
        if !isHex(candidate.checksum ?? "", length: 64) {
            failures.append(.missingChecksum)
        }
        if candidate.publishesPublicBinary {
            failures.append(.publicBinaryRelease)
        }
        if candidate.pullRequestBuildHasCISecrets {
            failures.append(.pullRequestSecretsEnabled)
        }

        return ReleaseGateResult(failures: failures)
    }

    private func isHex(_ value: String, length: Int) -> Bool {
        guard value.count == length else { return false }
        return value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(String(character).lowercased())
        }
    }
}
