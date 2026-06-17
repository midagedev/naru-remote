import Foundation

public enum AppleRemoteDesktopSupportTier: String, Codable, Equatable, CaseIterable, Sendable {
    case vncCompatible
    case helperBacked
    case researchOnly
    case unsupported
}

public enum AppleRemoteDesktopCapabilityID: String, Codable, Equatable, CaseIterable, Sendable {
    case vncControlObserve = "appleScreenSharing.vncControlObserve"
    case additionalDisplays = "appleScreenSharing.additionalDisplays"
    case highPerformanceScreenSharing = "appleRemoteDesktop.highPerformanceScreenSharing"
    case systemStatus = "appleRemoteDesktop.systemStatus"
    case messageUser = "appleRemoteDesktop.messageUser"
    case fileStage = "appleRemoteDesktop.fileStage"
    case wakeOrKeepAwake = "appleRemoteDesktop.wakeOrKeepAwake"
    case lockScreen = "appleRemoteDesktop.lockScreen"
    case powerAction = "appleRemoteDesktop.powerAction"
    case shellCommand = "appleRemoteDesktop.shellCommand"
}

public enum AppleRemoteDesktopSafeSetupLabel: String, Codable, Equatable, CaseIterable, Sendable {
    case enableRemoteManagement
    case allowVNCViewers
    case usePrivateNetwork
    case publicEndpointWarning
    case selectDisplayPort
    case fullARDAdminUnavailableThroughVNC
    case helperRequired
    case helperUpgradeAvailable
    case helperCapabilityMissing
    case approvalRequired
    case separateCommandApprovalSpecRequired
    case appleSiliconRequired
    case macOSSonomaRequired
    case udp5900To5902Required
    case highBandwidthRequired
    case useNaruHelperVideo
}

public enum AppleRemoteDesktopCapabilityStatus: String, Codable, Equatable, CaseIterable, Sendable {
    case available
    case disabled
    case missing
    case permissionMissing
    case approvalRequired
    case researchOnly
    case unsupported
}

public struct AppleScreenSharingProfileHints: Codable, Equatable, Sendable {
    public static let defaultControlObservePort = 5900
    public static let additionalDisplayPorts = [5901, 5902]

    public let defaultPort: Int
    public let additionalDisplayPorts: [Int]
    public let requiresVNCViewerAllowed: Bool
    public let fullARDAdminAvailableThroughVNC: Bool
    public let publicInternetWarning: Bool
    public let helperUpgradeCandidate: Bool
    public let safeSetupLabels: [AppleRemoteDesktopSafeSetupLabel]

    public init(
        hostKind: ConnectionProfile.HostKind = .magicDNS,
        helperUpgradeCandidate: Bool = true
    ) {
        let isPublicEndpoint = hostKind == .advancedManualPublicEndpoint
        var labels: [AppleRemoteDesktopSafeSetupLabel] = [
            .enableRemoteManagement,
            .allowVNCViewers,
            .usePrivateNetwork,
            .fullARDAdminUnavailableThroughVNC
        ]
        if isPublicEndpoint {
            labels.append(.publicEndpointWarning)
        }
        if helperUpgradeCandidate {
            labels.append(.helperUpgradeAvailable)
        }

        self.defaultPort = Self.defaultControlObservePort
        self.additionalDisplayPorts = Self.additionalDisplayPorts
        self.requiresVNCViewerAllowed = true
        self.fullARDAdminAvailableThroughVNC = false
        self.publicInternetWarning = isPublicEndpoint
        self.helperUpgradeCandidate = helperUpgradeCandidate
        self.safeSetupLabels = labels
    }
}

public struct AppleRemoteDesktopSupportCapability: Codable, Equatable, Sendable {
    public let capabilityID: AppleRemoteDesktopCapabilityID
    public let tier: AppleRemoteDesktopSupportTier
    public let status: AppleRemoteDesktopCapabilityStatus
    public let defaultPort: Int?
    public let candidatePorts: [Int]
    public let requiresApproval: Bool
    public let safeSetupLabels: [AppleRemoteDesktopSafeSetupLabel]

    public init(
        capabilityID: AppleRemoteDesktopCapabilityID,
        tier: AppleRemoteDesktopSupportTier,
        status: AppleRemoteDesktopCapabilityStatus,
        defaultPort: Int? = nil,
        candidatePorts: [Int] = [],
        requiresApproval: Bool = false,
        safeSetupLabels: [AppleRemoteDesktopSafeSetupLabel] = []
    ) {
        self.capabilityID = capabilityID
        self.tier = tier
        self.status = status
        self.defaultPort = defaultPort
        self.candidatePorts = candidatePorts
        self.requiresApproval = requiresApproval
        self.safeSetupLabels = safeSetupLabels
    }
}

public enum ARDClassHelperCapability: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case systemStatus
    case messageUser
    case fileStage
    case wakeOrKeepAwake
    case lockScreen
    case powerAction
    case shellCommand
}

public enum ARDClassActionKind: String, Codable, Equatable, CaseIterable, Sendable {
    case showSystemStatus
    case messageUser
    case stageFile
    case keepAwake
    case lockScreen
    case sleep
    case logOut
    case restart
    case shellCommand

    public var requiredCapability: ARDClassHelperCapability {
        switch self {
        case .showSystemStatus:
            .systemStatus
        case .messageUser:
            .messageUser
        case .stageFile:
            .fileStage
        case .keepAwake:
            .wakeOrKeepAwake
        case .lockScreen:
            .lockScreen
        case .sleep, .logOut, .restart:
            .powerAction
        case .shellCommand:
            .shellCommand
        }
    }

    public var requiresExplicitApproval: Bool {
        switch self {
        case .showSystemStatus, .keepAwake:
            false
        case .messageUser, .stageFile, .lockScreen, .sleep, .logOut, .restart, .shellCommand:
            true
        }
    }
}

public struct ARDClassActionAvailability: Codable, Equatable, Sendable {
    public let actionKind: ARDClassActionKind
    public let tier: AppleRemoteDesktopSupportTier
    public let status: AppleRemoteDesktopCapabilityStatus
    public let requiredCapability: ARDClassHelperCapability
    public let requiresApproval: Bool
    public let safeSetupLabels: [AppleRemoteDesktopSafeSetupLabel]

    public var isEnabled: Bool {
        status == .available
    }
}

public enum ARDClassActionApprovalState: String, Codable, Equatable, CaseIterable, Sendable {
    case notRequired
    case required
    case approved
    case denied
    case expired
}

public enum ARDClassActionResultState: String, Codable, Equatable, CaseIterable, Sendable {
    case notStarted
    case sent
    case completed
    case failed
    case timedOut
    case cancelled
}

public struct ARDClassActionRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let actionKind: ARDClassActionKind
    public let approvalState: ARDClassActionApprovalState
    public let capabilityStatus: AppleRemoteDesktopCapabilityStatus
    public let resultState: ARDClassActionResultState

    public init(
        id: UUID = UUID(),
        actionKind: ARDClassActionKind,
        approvalState: ARDClassActionApprovalState,
        capabilityStatus: AppleRemoteDesktopCapabilityStatus,
        resultState: ARDClassActionResultState = .notStarted
    ) {
        self.id = id
        self.actionKind = actionKind
        self.approvalState = approvalState
        self.capabilityStatus = capabilityStatus
        self.resultState = resultState
    }
}

public enum AppleRemoteDesktopSupportCatalog {
    public static func appleScreenSharingProfileHints(
        hostKind: ConnectionProfile.HostKind = .magicDNS,
        helperUpgradeCandidate: Bool = true
    ) -> AppleScreenSharingProfileHints {
        AppleScreenSharingProfileHints(
            hostKind: hostKind,
            helperUpgradeCandidate: helperUpgradeCandidate
        )
    }

    public static var vncControlObserve: AppleRemoteDesktopSupportCapability {
        AppleRemoteDesktopSupportCapability(
            capabilityID: .vncControlObserve,
            tier: .vncCompatible,
            status: .available,
            defaultPort: AppleScreenSharingProfileHints.defaultControlObservePort,
            safeSetupLabels: [
                .enableRemoteManagement,
                .allowVNCViewers,
                .usePrivateNetwork,
                .fullARDAdminUnavailableThroughVNC
            ]
        )
    }

    public static var additionalDisplays: AppleRemoteDesktopSupportCapability {
        AppleRemoteDesktopSupportCapability(
            capabilityID: .additionalDisplays,
            tier: .vncCompatible,
            status: .available,
            candidatePorts: AppleScreenSharingProfileHints.additionalDisplayPorts,
            safeSetupLabels: [.selectDisplayPort]
        )
    }

    public static var highPerformanceScreenSharing: AppleRemoteDesktopSupportCapability {
        AppleRemoteDesktopSupportCapability(
            capabilityID: .highPerformanceScreenSharing,
            tier: .researchOnly,
            status: .researchOnly,
            candidatePorts: [5900, 5901, 5902],
            safeSetupLabels: [
                .appleSiliconRequired,
                .macOSSonomaRequired,
                .udp5900To5902Required,
                .highBandwidthRequired,
                .useNaruHelperVideo
            ]
        )
    }

    public static func helperBackedActionAvailability(
        for actionKind: ARDClassActionKind,
        advertisedCapabilities: Set<ARDClassHelperCapability>,
        isHelperPaired: Bool,
        isPrivateProfile: Bool,
        hasUserApproval: Bool = false
    ) -> ARDClassActionAvailability {
        let requiredCapability = actionKind.requiredCapability
        var labels: [AppleRemoteDesktopSafeSetupLabel] = [.helperRequired]

        guard actionKind != .shellCommand else {
            return ARDClassActionAvailability(
                actionKind: actionKind,
                tier: .helperBacked,
                status: .unsupported,
                requiredCapability: requiredCapability,
                requiresApproval: true,
                safeSetupLabels: labels + [.separateCommandApprovalSpecRequired]
            )
        }

        guard isPrivateProfile else {
            return ARDClassActionAvailability(
                actionKind: actionKind,
                tier: .helperBacked,
                status: .unsupported,
                requiredCapability: requiredCapability,
                requiresApproval: actionKind.requiresExplicitApproval,
                safeSetupLabels: labels + [.usePrivateNetwork]
            )
        }

        guard isHelperPaired else {
            return ARDClassActionAvailability(
                actionKind: actionKind,
                tier: .helperBacked,
                status: .missing,
                requiredCapability: requiredCapability,
                requiresApproval: actionKind.requiresExplicitApproval,
                safeSetupLabels: labels
            )
        }

        guard advertisedCapabilities.contains(requiredCapability) else {
            return ARDClassActionAvailability(
                actionKind: actionKind,
                tier: .helperBacked,
                status: .missing,
                requiredCapability: requiredCapability,
                requiresApproval: actionKind.requiresExplicitApproval,
                safeSetupLabels: labels + [.helperCapabilityMissing]
            )
        }

        if actionKind.requiresExplicitApproval && !hasUserApproval {
            labels.append(.approvalRequired)
            return ARDClassActionAvailability(
                actionKind: actionKind,
                tier: .helperBacked,
                status: .approvalRequired,
                requiredCapability: requiredCapability,
                requiresApproval: true,
                safeSetupLabels: labels
            )
        }

        return ARDClassActionAvailability(
            actionKind: actionKind,
            tier: .helperBacked,
            status: .available,
            requiredCapability: requiredCapability,
            requiresApproval: false,
            safeSetupLabels: labels
        )
    }

    public static var safeDiagnosticCapabilities: [AppleRemoteDesktopSupportCapability] {
        [
            vncControlObserve,
            additionalDisplays,
            highPerformanceScreenSharing
        ]
    }
}
