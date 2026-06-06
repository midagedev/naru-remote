import Foundation

#if os(macOS) && canImport(CoreGraphics)
import CoreGraphics
#endif

public struct BenchmarkLiveEnvironmentPreflightReport: Codable, Equatable {
    public static let schemaVersion = 4

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hostStatus
        case portStatus
        case credentialStatus
        case stimulusMode
        case stimulusCommandStatus
        case helperVideoScreenCapturePermissionStatus
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
    public let helperVideoScreenCapturePermissionStatus:
        BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus
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
        helperVideoScreenCapturePermissionStatus:
            BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus = .notRequired,
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
        self.helperVideoScreenCapturePermissionStatus = helperVideoScreenCapturePermissionStatus
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
        let helperVideoScreenCapturePermissionStatus = try container.decodeIfPresent(
            BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus.self,
            forKey: .helperVideoScreenCapturePermissionStatus
        ) ?? .notRequired
        let canRunLiveBenchmark = try container.decode(Bool.self, forKey: .canRunLiveBenchmark)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.schemaVersion,
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
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
                helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
                canRunLiveBenchmark: canRunLiveBenchmark
            )
        )
    }

    public static func make(
        environment: [String: String],
        askPassword: Bool,
        stimulusMode: BenchmarkStreamShapeStimulusMode,
        visualTransports: BenchmarkVisualTransportSelection = .vnc,
        helperVideoProbeMode: BenchmarkHelperVideoProbeMode = .disabled,
        screenCapturePermissionStatusProvider:
            (() -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus)? = nil
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
        let helperVideoScreenCapturePermissionStatus = helperVideoScreenCapturePermissionStatus(
            visualTransports: visualTransports,
            helperVideoProbeMode: helperVideoProbeMode,
            provider: screenCapturePermissionStatusProvider ?? liveScreenCapturePermissionStatus
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
        if helperVideoScreenCapturePermissionStatus == .missing {
            issueCodes.append(.helperVideoPermissionMissing)
        }
        if helperVideoScreenCapturePermissionStatus == .unsupported {
            issueCodes.append(.helperVideoCaptureUnsupported)
        }
        let canRunLiveBenchmark = issueCodes.isEmpty

        return BenchmarkLiveEnvironmentPreflightReport(
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
            canRunLiveBenchmark: canRunLiveBenchmark,
            issueCodes: issueCodes,
            setupActionLabels: setupActions(
                hostStatus: hostStatus,
                portStatus: portStatus,
                credentialStatus: credentialStatus,
                stimulusCommandStatus: stimulusCommandStatus,
                helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
                canRunLiveBenchmark: canRunLiveBenchmark
            )
        )
    }

    private static func setupActions(
        hostStatus: BenchmarkLiveEnvironmentPreflightHostStatus,
        portStatus: BenchmarkLiveEnvironmentPreflightPortStatus,
        credentialStatus: BenchmarkLiveEnvironmentPreflightCredentialStatus,
        stimulusCommandStatus: BenchmarkLiveEnvironmentPreflightStimulusCommandStatus,
        helperVideoScreenCapturePermissionStatus:
            BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus,
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
        if helperVideoScreenCapturePermissionStatus == .missing {
            actions.append(.requestHelperVideoScreenRecordingPermission)
        }
        if helperVideoScreenCapturePermissionStatus == .unsupported {
            actions.append(.useSyntheticHelperVideoProbe)
        }
        return actions
    }

    private static func helperVideoScreenCapturePermissionStatus(
        visualTransports: BenchmarkVisualTransportSelection,
        helperVideoProbeMode: BenchmarkHelperVideoProbeMode,
        provider: () -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus
    ) -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus {
        guard visualTransports.transports.contains(.helperVideo),
              helperVideoProbeMode.requiresScreenCapturePermission else {
            return .notRequired
        }
        if helperVideoProbeMode.delegatesScreenCapturePermissionToExternalHelper {
            return .delegatedToHelper
        }
        return provider()
    }

    private static func liveScreenCapturePermissionStatus()
        -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus
    {
        #if os(macOS) && canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess() ? .granted : .missing
        #else
        return .unsupported
        #endif
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

public enum BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus: String, Codable, Equatable {
    case notRequired
    case granted
    case missing
    case unsupported
    case delegatedToHelper
}

public enum BenchmarkLiveEnvironmentPreflightIssueCode: String, Codable, Equatable {
    case missingHost = "missing-host"
    case invalidPort = "invalid-port"
    case missingCredential = "missing-credential"
    case missingStimulusCommand = "missing-stimulus-command"
    case helperVideoPermissionMissing = "helper-video-permission-missing"
    case helperVideoCaptureUnsupported = "helper-video-capture-unsupported"
}

public enum BenchmarkLiveEnvironmentPreflightSetupAction: String, Codable, Equatable {
    case setHost = "set-naru-live-mac-host"
    case fixPort = "fix-naru-live-mac-port"
    case provideCredentialOrAskPassword = "provide-credential-or-ask-password"
    case setStimulusCommand = "set-naru-live-stimulus-command"
    case requestHelperVideoScreenRecordingPermission =
        "request-helper-video-screen-recording-permission"
    case useSyntheticHelperVideoProbe = "use-synthetic-helper-video-probe"
    case runLiveGate = "run-live-gate"
}

private extension BenchmarkHelperVideoProbeMode {
    var requiresScreenCapturePermission: Bool {
        switch self {
        case .screenCaptureKitTCP, .externalHelperScreenCaptureKitTCP:
            return true
        case .disabled, .syntheticTCP, .syntheticEncodedTCP, .externalHelperSyntheticEncodedTCP:
            return false
        }
    }

    var delegatesScreenCapturePermissionToExternalHelper: Bool {
        self == .externalHelperScreenCaptureKitTCP
    }
}
