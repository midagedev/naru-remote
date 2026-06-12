import Foundation
import NaruHelperKit

#if os(macOS) && canImport(CoreGraphics)
import CoreGraphics
#endif

public struct BenchmarkLiveEnvironmentPreflightReport: Codable, Equatable {
    public static let schemaVersion = 7

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case hostStatus
        case portStatus
        case credentialStatus
        case stimulusMode
        case stimulusCommandStatus
        case helperVideoScreenCapturePermissionStatus
        case helperVideoExternalCapability
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
    public let helperVideoExternalCapability:
        BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability
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
        helperVideoExternalCapability:
            BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability = .notRequired,
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
        self.helperVideoExternalCapability = helperVideoExternalCapability
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
        let helperVideoExternalCapability = try container.decodeIfPresent(
            BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability.self,
            forKey: .helperVideoExternalCapability
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
            helperVideoExternalCapability: helperVideoExternalCapability,
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
                helperVideoExternalCapability: helperVideoExternalCapability,
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
            (() -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus)? = nil,
        externalHelperCapabilityProvider:
            (() -> BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability)? = nil
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
        let helperVideoExternalCapability = helperVideoExternalCapability(
            visualTransports: visualTransports,
            helperVideoProbeMode: helperVideoProbeMode,
            provider: externalHelperCapabilityProvider ?? {
                liveExternalHelperCapability(environment: environment)
            }
        )
        let helperVideoScreenCapturePermissionStatus = helperVideoScreenCapturePermissionStatus(
            visualTransports: visualTransports,
            helperVideoProbeMode: helperVideoProbeMode,
            externalHelperCapability: helperVideoExternalCapability,
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
        if helperVideoExternalCapability.status == .unavailable {
            issueCodes.append(.helperVideoExternalHelperUnavailable)
        }
        if helperVideoExternalCapability.status == .failed {
            issueCodes.append(.helperVideoExternalHelperFailed)
        }
        if helperVideoExternalCapability.status == .timedOut {
            issueCodes.append(.helperVideoExternalHelperTimedOut)
        }
        let canRunLiveBenchmark = issueCodes.isEmpty

        return BenchmarkLiveEnvironmentPreflightReport(
            hostStatus: hostStatus,
            portStatus: portStatus,
            credentialStatus: credentialStatus,
            stimulusMode: stimulusMode,
            stimulusCommandStatus: stimulusCommandStatus,
            helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
            helperVideoExternalCapability: helperVideoExternalCapability,
            canRunLiveBenchmark: canRunLiveBenchmark,
            issueCodes: issueCodes,
            setupActionLabels: setupActions(
                hostStatus: hostStatus,
                portStatus: portStatus,
                credentialStatus: credentialStatus,
                stimulusCommandStatus: stimulusCommandStatus,
                helperVideoScreenCapturePermissionStatus: helperVideoScreenCapturePermissionStatus,
                helperVideoExternalCapability: helperVideoExternalCapability,
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
        helperVideoExternalCapability:
            BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability,
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
            actions.append(
                contentsOf: setupActionsForMissingHelperVideoPermission(
                    externalHelperCapability: helperVideoExternalCapability
                )
            )
        }
        if helperVideoScreenCapturePermissionStatus == .unsupported {
            actions.append(.useSyntheticHelperVideoProbe)
        }
        if helperVideoExternalCapability.status == .unavailable {
            actions.append(.configureHelperVideoExecutable)
        }
        if helperVideoExternalCapability.status == .failed {
            actions.append(.inspectHelperVideoCapability)
        }
        if helperVideoExternalCapability.status == .timedOut {
            actions.append(.inspectHelperVideoCapability)
        }
        return actions
    }

    private static func setupActionsForMissingHelperVideoPermission(
        externalHelperCapability:
            BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability
    ) -> [BenchmarkLiveEnvironmentPreflightSetupAction] {
        switch externalHelperCapability.permissionIdentity?.grantHint {
        case .grantAppBundle:
            return [
                .runScreenRecordingWatch,
                .grantHelperVideoAppScreenRecordingPermission
            ]
        case .useStableHelperExecutable:
            return [.installStableHelperVideoExecutable]
        case .grantCurrentHelperExecutable, .unsupported, .unknown, nil:
            return [.requestHelperVideoScreenRecordingPermission]
        }
    }

    private static func helperVideoScreenCapturePermissionStatus(
        visualTransports: BenchmarkVisualTransportSelection,
        helperVideoProbeMode: BenchmarkHelperVideoProbeMode,
        externalHelperCapability:
            BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability,
        provider: () -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus
    ) -> BenchmarkLiveEnvironmentPreflightHelperVideoScreenCapturePermissionStatus {
        guard visualTransports.transports.contains(.helperVideo),
              helperVideoProbeMode.requiresScreenCapturePermission else {
            return .notRequired
        }
        if helperVideoProbeMode.usesExternalHelperScreenCapture {
            switch externalHelperCapability.status {
            case .available:
                return .granted
            case .permissionMissing:
                return .missing
            case .unsupported:
                return .unsupported
            case .notRequired, .notChecked, .unavailable, .failed, .timedOut:
                return .delegatedToHelper
            }
        }
        if helperVideoProbeMode.delegatesScreenCapturePermissionToExternalHelper {
            return .delegatedToHelper
        }
        return provider()
    }

    private static func helperVideoExternalCapability(
        visualTransports: BenchmarkVisualTransportSelection,
        helperVideoProbeMode: BenchmarkHelperVideoProbeMode,
        provider: () -> BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability
    ) -> BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability {
        guard visualTransports.transports.contains(.helperVideo),
              helperVideoProbeMode.usesExternalHelperScreenCapture
        else {
            return .notRequired
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

    private static func liveExternalHelperCapability(
        environment: [String: String]
    ) -> BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability {
        let timeout = helperCapabilityTimeout(environment: environment)
        let process = Process()
        process.executableURL = helperExecutableURL(environment: environment)
        process.arguments = ["--video-capability"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(
                status: .unavailable
            )
        }
        guard BenchmarkProcessWaiter.waitForExit(process, timeout: timeout) else {
            BenchmarkProcessWaiter.terminateAndWait(process)
            return BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(
                status: .timedOut
            )
        }

        guard process.terminationStatus == 0 else {
            return BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(
                status: .failed
            )
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let response = try? JSONDecoder().decode(
            NaruHelperVideoCaptureCapabilityResponse.self,
            from: data
        ) else {
            return BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(
                status: .failed
            )
        }
        return BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(response: response)
    }

    private static func helperCapabilityTimeout(environment: [String: String]) -> TimeInterval {
        guard let rawTimeout = environment["NARU_HELPER_CAPABILITY_TIMEOUT_SECONDS"],
              let parsedTimeout = TimeInterval(rawTimeout)
        else {
            return 3
        }
        return min(max(parsedTimeout, 0.05), 30)
    }

    private static func helperExecutableURL(environment: [String: String]) -> URL {
        if let executablePath = environment["NARU_HELPER_EXECUTABLE"],
           !executablePath.isEmpty
        {
            return fileURL(forExecutablePath: executablePath)
        }
        for productsDirectoryKey in ["BUILT_PRODUCTS_DIR", "CONFIGURATION_BUILD_DIR"] {
            guard let productsDirectory = environment[productsDirectoryKey],
                  !productsDirectory.isEmpty
            else {
                continue
            }
            return fileURL(forExecutablePath: productsDirectory)
                .appendingPathComponent("NaruHelper")
        }
        return fileURL(forExecutablePath: ".build/debug/NaruHelper")
    }

    private static func fileURL(forExecutablePath executablePath: String) -> URL {
        guard executablePath.hasPrefix("/") else {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(executablePath)
        }
        return URL(fileURLWithPath: executablePath)
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

public struct BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability:
    Codable,
    Equatable,
    Sendable
{
    public var status: BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapabilityStatus
    public var permissionIdentity:
        BenchmarkLiveEnvironmentPreflightHelperVideoPermissionIdentity?

    public init(
        status: BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapabilityStatus,
        permissionIdentity:
            BenchmarkLiveEnvironmentPreflightHelperVideoPermissionIdentity? = nil
    ) {
        self.status = status
        self.permissionIdentity = permissionIdentity
    }

    public init(response: NaruHelperVideoCaptureCapabilityResponse) {
        self.status = BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapabilityStatus(
            response: response
        )
        self.permissionIdentity = BenchmarkLiveEnvironmentPreflightHelperVideoPermissionIdentity(
            response.permissionIdentity
        )
    }

    public static let notRequired = BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapability(
        status: .notRequired
    )
}

public enum BenchmarkLiveEnvironmentPreflightHelperVideoExternalCapabilityStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case notRequired
    case notChecked
    case available
    case permissionMissing
    case unsupported
    case unavailable
    case failed
    case timedOut

    init(response: NaruHelperVideoCaptureCapabilityResponse) {
        switch response.availability {
        case .available:
            self = .available
        case .permissionMissing:
            self = .permissionMissing
        case .failed:
            self = response.screenRecordingPermission == .unsupported ? .unsupported : .failed
        case .notConfigured, .disabled, .checking, .revoked, .unreachable,
             .privateNetworkRequired:
            self = .unavailable
        case .codecUnsupported:
            self = .failed
        }
    }
}

public struct BenchmarkLiveEnvironmentPreflightHelperVideoPermissionIdentity:
    Codable,
    Equatable,
    Sendable
{
    public var processKind:
        BenchmarkLiveEnvironmentPreflightHelperVideoPermissionProcessKind
    public var grantHint:
        BenchmarkLiveEnvironmentPreflightHelperVideoPermissionGrantHint

    public init(
        processKind: BenchmarkLiveEnvironmentPreflightHelperVideoPermissionProcessKind,
        grantHint: BenchmarkLiveEnvironmentPreflightHelperVideoPermissionGrantHint
    ) {
        self.processKind = processKind
        self.grantHint = grantHint
    }

    init(_ context: NaruHelperVideoPermissionIdentityContext) {
        self.processKind = BenchmarkLiveEnvironmentPreflightHelperVideoPermissionProcessKind(
            context.processKind
        )
        self.grantHint = BenchmarkLiveEnvironmentPreflightHelperVideoPermissionGrantHint(
            context.grantHint
        )
    }
}

public enum BenchmarkLiveEnvironmentPreflightHelperVideoPermissionProcessKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case appBundle
    case commandLineTool
    case swiftPMBuildArtifact
    case unsupported
    case unknown

    init(_ processKind: NaruHelperVideoPermissionProcessKind) {
        self = BenchmarkLiveEnvironmentPreflightHelperVideoPermissionProcessKind(
            rawValue: processKind.rawValue
        ) ?? .unknown
    }
}

public enum BenchmarkLiveEnvironmentPreflightHelperVideoPermissionGrantHint:
    String,
    Codable,
    Equatable,
    Sendable
{
    case grantAppBundle
    case grantCurrentHelperExecutable
    case useStableHelperExecutable
    case unsupported
    case unknown

    init(_ grantHint: NaruHelperVideoPermissionGrantHint) {
        self = BenchmarkLiveEnvironmentPreflightHelperVideoPermissionGrantHint(
            rawValue: grantHint.rawValue
        ) ?? .unknown
    }
}

public enum BenchmarkLiveEnvironmentPreflightIssueCode: String, Codable, Equatable {
    case missingHost = "missing-host"
    case invalidPort = "invalid-port"
    case missingCredential = "missing-credential"
    case missingStimulusCommand = "missing-stimulus-command"
    case helperVideoPermissionMissing = "helper-video-permission-missing"
    case helperVideoCaptureUnsupported = "helper-video-capture-unsupported"
    case helperVideoExternalHelperUnavailable = "helper-video-external-helper-unavailable"
    case helperVideoExternalHelperFailed = "helper-video-external-helper-failed"
    case helperVideoExternalHelperTimedOut = "helper-video-external-helper-timed-out"
}

public enum BenchmarkLiveEnvironmentPreflightSetupAction: String, Codable, Equatable {
    case setHost = "set-naru-live-mac-host"
    case fixPort = "fix-naru-live-mac-port"
    case provideCredentialOrAskPassword = "provide-credential-or-ask-password"
    case setStimulusCommand = "set-naru-live-stimulus-command"
    case requestHelperVideoScreenRecordingPermission =
        "request-helper-video-screen-recording-permission"
    case grantHelperVideoAppScreenRecordingPermission =
        "grant-helper-video-app-screen-recording-permission"
    case runScreenRecordingWatch = "run-screen-recording-watch"
    case installStableHelperVideoExecutable = "install-stable-helper-video-executable"
    case configureHelperVideoExecutable = "configure-helper-video-executable"
    case inspectHelperVideoCapability = "inspect-helper-video-capability"
    case useSyntheticHelperVideoProbe = "use-synthetic-helper-video-probe"
    case runLiveGate = "run-live-gate"
}

private extension BenchmarkHelperVideoProbeMode {
    var requiresScreenCapturePermission: Bool {
        switch self {
        case .screenCaptureKitTCP,
             .externalHelperScreenCaptureKitTCP,
             .externalHelperSustainedScreenCaptureKitTCP:
            return true
        case .disabled,
             .syntheticTCP,
             .syntheticEncodedTCP,
             .externalHelperSyntheticEncodedTCP,
             .externalHelperSustainedSyntheticEncodedTCP:
            return false
        }
    }

    var delegatesScreenCapturePermissionToExternalHelper: Bool {
        self == .externalHelperScreenCaptureKitTCP
            || self == .externalHelperSustainedScreenCaptureKitTCP
    }

    var usesExternalHelperScreenCapture: Bool {
        self == .externalHelperScreenCaptureKitTCP
            || self == .externalHelperSustainedScreenCaptureKitTCP
    }
}
