import Foundation

public struct BenchmarkLiveEnvironmentPreflightReport: Codable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus
    public let portStatus: BenchmarkLiveEnvironmentPreflightPortStatus
    public let credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus
    public let stimulusMode: BenchmarkStreamShapeStimulusMode
    public let stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus
    public let canRunLiveBenchmark: Bool
    public let issueCodes: [BenchmarkLiveEnvironmentPreflightIssueCode]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus,
        portStatus: BenchmarkLiveEnvironmentPreflightPortStatus,
        credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus,
        stimulusMode: BenchmarkStreamShapeStimulusMode,
        stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus,
        canRunLiveBenchmark: Bool,
        issueCodes: [BenchmarkLiveEnvironmentPreflightIssueCode]
    ) {
        self.schemaVersion = schemaVersion
        self.hostStatus = hostStatus
        self.portStatus = portStatus
        self.credentialStatus = credentialStatus
        self.stimulusMode = stimulusMode
        self.stimulusCommandStatus = stimulusCommandStatus
        self.canRunLiveBenchmark = canRunLiveBenchmark
        self.issueCodes = issueCodes
    }

    public static func make(
        environment: [String: String],
        askPassword: Bool,
        stimulusMode: BenchmarkStreamShapeStimulusMode
    ) -> BenchmarkLiveEnvironmentPreflightReport {
        let hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus
        if environment["NARU_LIVE_MAC_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            hostStatus = .configured
        } else {
            hostStatus = .missing
        }

        let portStatus = BenchmarkLiveEnvironmentPreflightPortStatus.status(
            for: environment["NARU_LIVE_MAC_PORT"]
        )

        let credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus
        if environment["NARU_LIVE_MAC_PASSWORD"]?.isEmpty == false {
            credentialStatus = .environment
        } else if askPassword {
            credentialStatus = .promptRequested
        } else {
            credentialStatus = .missing
        }

        let stimulusCommandStatus = BenchmarkLiveEnvironmentPreflightStimulusCommandStatus.status(
            for: stimulusMode,
            environment: environment
        )

        var issueCodes: [BenchmarkLiveEnvironmentPreflightIssueCode] = []
        if hostStatus == .missing {
            issueCodes.append(.missingHost)
        }
        if portStatus == .invalid {
            issueCodes.append(.invalidPort)
        }
        if credentialStatus == .missing {
            issueCodes.append(.missingCredential)
        }
        if stimulusCommandStatus == .requiredMissing {
            issueCodes.append(.missingStimulusCommand)
        }

        return BenchmarkLiveEnvironmentPreflightReport(
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            canRunLiveBenchmark: issueCodes.isEmpty,
            issueCodes: issueCodes
        )
    }
}

public enum BenchmarkLiveEnvironmentPreflightHostStatus: String, Codable, Equatable {
    case configured
    case missing
}

public enum BenchmarkLiveEnvironmentPreflightPortStatus: String, Codable, Equatable {
    case defaulted
    case configured
    case invalid

    static func status(for rawPort: String?) -> BenchmarkLiveEnvironmentPreflightPortStatus {
        guard let rawPort, !rawPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .defaulted
        }
        guard let port = UInt16(rawPort), port > 0 else {
            return .invalid
        }
        return .configured
    }
}

public enum BenchmarkLiveEnvironmentPreflightCredentialStatus: String, Codable, Equatable {
    case environment
    case promptRequested
    case missing
}

public enum BenchmarkLiveEnvironmentPreflightStimulusCommandStatus: String, Codable, Equatable {
    case notRequired
    case configured
    case requiredMissing

    static func status(
        for stimulusMode: BenchmarkStreamShapeStimulusMode,
        environment: [String: String]
    ) -> BenchmarkLiveEnvironmentPreflightStimulusCommandStatus {
        guard stimulusMode == .externalCommand else {
            return .notRequired
        }
        if environment[BenchmarkStreamShapeStimulusEnvironment.commandKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false {
            return .configured
        }
        return .requiredMissing
    }
}

public enum BenchmarkLiveEnvironmentPreflightIssueCode: String, Codable, Equatable {
    case missingHost = "missing-host"
    case invalidPort = "invalid-port"
    case missingCredential = "missing-credential"
    case missingStimulusCommand = "missing-stimulus-command"
}
