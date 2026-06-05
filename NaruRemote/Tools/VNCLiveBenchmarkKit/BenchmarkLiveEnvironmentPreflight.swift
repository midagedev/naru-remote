import Foundation

public struct BenchmarkLiveEnvironmentPreflightReport: Codable, Equatable {
    public static let schemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hostStatus
        case portStatus
        case credentialStatus
        case stimulusMode
        case stimulusCommandStatus
        case canRunLiveBenchmark
        case issueCodes
        case setupActionLabels
    }

    public let schemaVersion: Int
    public let hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus
    public let portStatus: BenchmarkLiveEnvironmentPreflightPortStatus
    public let credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus
    public let stimulusMode: BenchmarkStreamShapeStimulusMode
    public let stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus
    public let canRunLiveBenchmark: Bool
    public let issueCodes: [BenchmarkLiveEnvironmentPreflightIssueCode]
    public let setupActionLabels: [BenchmarkLiveEnvironmentPreflightSetupAction]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus,
        portStatus: BenchmarkLiveEnvironmentPreflightPortStatus,
        credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus,
        stimulusMode: BenchmarkStreamShapeStimulusMode,
        stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus,
        canRunLiveBenchmark: Bool,
        issueCodes: [BenchmarkLiveEnvironmentPreflightIssueCode],
        setupActionLabels: [BenchmarkLiveEnvironmentPreflightSetupAction] = []
    ) {
        self.schemaVersion = schemaVersion
        self.hostStatus = hostStatus
        self.portStatus = portStatus
        self.credentialStatus = credentialStatus
        self.stimulusMode = stimulusMode
        self.stimulusCommandStatus = stimulusCommandStatus
        self.canRunLiveBenchmark = canRunLiveBenchmark
        self.issueCodes = issueCodes
        self.setupActionLabels = setupActionLabels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hostStatus = try container.decode(
            BenchmarkLiveEnvironmentPreflightHostStatus.self,
            forKey: .hostStatus
        )
        let portStatus = try container.decode(
            BenchmarkLiveEnvironmentPreflightPortStatus.self,
            forKey: .portStatus
        )
        let credentialStatus = try container.decode(
            BenchmarkLiveEnvironmentPreflightCredentialStatus.self,
            forKey: .credentialStatus
        )
        let stimulusMode = try container.decode(
            BenchmarkStreamShapeStimulusMode.self,
            forKey: .stimulusMode
        )
        let stimulusCommandStatus = try container.decode(
            BenchmarkLiveEnvironmentPreflightStimulusCommandStatus.self,
            forKey: .stimulusCommandStatus
        )
        let canRunLiveBenchmark = try container.decode(Bool.self, forKey: .canRunLiveBenchmark)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.schemaVersion,
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            canRunLiveBenchmark: canRunLiveBenchmark,
            issueCodes: try container.decodeIfPresent(
                [BenchmarkLiveEnvironmentPreflightIssueCode].self,
                forKey: .issueCodes
            ) ?? [],
            setupActionLabels: try container.decodeIfPresent(
                [BenchmarkLiveEnvironmentPreflightSetupAction].self,
                forKey: .setupActionLabels
            ) ?? Self.setupActions(
                hostStatus: hostStatus,
                portStatus: portStatus,
                credentialStatus: credentialStatus,
                stimulusCommandStatus: stimulusCommandStatus,
                canRunLiveBenchmark: canRunLiveBenchmark
            )
        )
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
        let canRunLiveBenchmark = issueCodes.isEmpty

        return BenchmarkLiveEnvironmentPreflightReport(
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            canRunLiveBenchmark: canRunLiveBenchmark,
            issueCodes: issueCodes,
            setupActionLabels: setupActions(
                hostStatus: hostStatus,
                portStatus: portStatus,
                credentialStatus: credentialStatus,
                stimulusCommandStatus: stimulusCommandStatus,
                canRunLiveBenchmark: canRunLiveBenchmark
            )
        )
    }

    private static func setupActions(
        hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus,
        portStatus: BenchmarkLiveEnvironmentPreflightPortStatus,
        credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus,
        stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus,
        canRunLiveBenchmark: Bool
    ) -> [BenchmarkLiveEnvironmentPreflightSetupAction] {
        guard !canRunLiveBenchmark else {
            return [.runLiveGate]
        }

        var actions: [BenchmarkLiveEnvironmentPreflightSetupAction] = []
        if hostStatus == .missing {
            actions.append(.setHost)
        }
        if portStatus == .invalid {
            actions.append(.fixPort)
        }
        if credentialStatus == .missing {
            actions.append(.provideCredentialOrAskPassword)
        }
        if stimulusCommandStatus == .requiredMissing {
            actions.append(.setStimulusCommand)
        }
        return actions
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

public enum BenchmarkLiveEnvironmentPreflightSetupAction: String, Codable, Equatable {
    case setHost = "set-naru-live-mac-host"
    case fixPort = "fix-naru-live-mac-port"
    case provideCredentialOrAskPassword = "provide-credential-or-ask-password"
    case setStimulusCommand = "set-naru-live-stimulus-command"
    case runLiveGate = "run-live-gate"
}
