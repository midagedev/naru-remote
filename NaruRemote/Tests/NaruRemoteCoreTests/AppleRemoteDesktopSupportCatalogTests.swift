import XCTest
@testable import NaruRemoteCore

final class AppleRemoteDesktopSupportCatalogTests: XCTestCase {
    func testAppleScreenSharingDefaultsToVNCControlPortAndNoFullARDAdmin() {
        let hints = AppleRemoteDesktopSupportCatalog.appleScreenSharingProfileHints()
        let capability = AppleRemoteDesktopSupportCatalog.vncControlObserve

        XCTAssertEqual(hints.defaultPort, 5900)
        XCTAssertEqual(capability.defaultPort, 5900)
        XCTAssertEqual(capability.tier, .vncCompatible)
        XCTAssertEqual(capability.status, .available)
        XCTAssertTrue(hints.requiresVNCViewerAllowed)
        XCTAssertFalse(hints.fullARDAdminAvailableThroughVNC)
        XCTAssertTrue(hints.safeSetupLabels.contains(.allowVNCViewers))
        XCTAssertTrue(hints.safeSetupLabels.contains(.fullARDAdminUnavailableThroughVNC))
        XCTAssertTrue(hints.safeSetupLabels.contains(.helperUpgradeAvailable))
        XCTAssertFalse(hints.safeSetupLabels.contains(.helperRequired))
    }

    func testAdditionalDisplayPortsAreFixedAppleScreenSharingCandidates() {
        let hints = AppleRemoteDesktopSupportCatalog.appleScreenSharingProfileHints()
        let capability = AppleRemoteDesktopSupportCatalog.additionalDisplays

        XCTAssertEqual(hints.additionalDisplayPorts, [5901, 5902])
        XCTAssertEqual(capability.candidatePorts, [5901, 5902])
        XCTAssertEqual(capability.tier, .vncCompatible)
        XCTAssertEqual(capability.safeSetupLabels, [.selectDisplayPort])
    }

    func testPublicEndpointProfilesReceiveWarningWithoutChangingDefaultPort() {
        let hints = AppleRemoteDesktopSupportCatalog.appleScreenSharingProfileHints(
            hostKind: .advancedManualPublicEndpoint
        )

        XCTAssertEqual(hints.defaultPort, 5900)
        XCTAssertTrue(hints.publicInternetWarning)
        XCTAssertTrue(hints.safeSetupLabels.contains(.publicEndpointWarning))
    }

    func testHelperBackedActionsRequireHelperCapabilityAndApproval() {
        let hidden = AppleRemoteDesktopSupportCatalog.helperBackedActionAvailability(
            for: .messageUser,
            advertisedCapabilities: [],
            isHelperPaired: true,
            isPrivateProfile: true
        )
        XCTAssertEqual(hidden.tier, .helperBacked)
        XCTAssertEqual(hidden.status, .missing)
        XCTAssertFalse(hidden.isEnabled)
        XCTAssertTrue(hidden.safeSetupLabels.contains(.helperCapabilityMissing))

        let approvalRequired = AppleRemoteDesktopSupportCatalog.helperBackedActionAvailability(
            for: .messageUser,
            advertisedCapabilities: [.messageUser],
            isHelperPaired: true,
            isPrivateProfile: true
        )
        XCTAssertEqual(approvalRequired.status, .approvalRequired)
        XCTAssertTrue(approvalRequired.requiresApproval)
        XCTAssertTrue(approvalRequired.safeSetupLabels.contains(.approvalRequired))

        let available = AppleRemoteDesktopSupportCatalog.helperBackedActionAvailability(
            for: .messageUser,
            advertisedCapabilities: [.messageUser],
            isHelperPaired: true,
            isPrivateProfile: true,
            hasUserApproval: true
        )
        XCTAssertEqual(available.status, .available)
        XCTAssertTrue(available.isEnabled)
        XCTAssertFalse(available.requiresApproval)
    }

    func testHelperBackedActionsStayDisabledOnPublicProfiles() {
        let availability = AppleRemoteDesktopSupportCatalog.helperBackedActionAvailability(
            for: .lockScreen,
            advertisedCapabilities: [.lockScreen],
            isHelperPaired: true,
            isPrivateProfile: false,
            hasUserApproval: true
        )

        XCTAssertEqual(availability.status, .unsupported)
        XCTAssertFalse(availability.isEnabled)
        XCTAssertTrue(availability.safeSetupLabels.contains(.usePrivateNetwork))
    }

    func testShellCommandIsReservedForSeparateApprovalSpec() {
        let availability = AppleRemoteDesktopSupportCatalog.helperBackedActionAvailability(
            for: .shellCommand,
            advertisedCapabilities: [.shellCommand],
            isHelperPaired: true,
            isPrivateProfile: true,
            hasUserApproval: true
        )

        XCTAssertEqual(availability.status, .unsupported)
        XCTAssertFalse(availability.isEnabled)
        XCTAssertTrue(availability.safeSetupLabels.contains(.separateCommandApprovalSpecRequired))
    }

    func testHighPerformanceScreenSharingIsResearchOnlyAndRoutesToHelperVideo() {
        let capability = AppleRemoteDesktopSupportCatalog.highPerformanceScreenSharing

        XCTAssertEqual(capability.tier, .researchOnly)
        XCTAssertEqual(capability.status, .researchOnly)
        XCTAssertEqual(capability.candidatePorts, [5900, 5901, 5902])
        XCTAssertTrue(capability.safeSetupLabels.contains(.appleSiliconRequired))
        XCTAssertTrue(capability.safeSetupLabels.contains(.udp5900To5902Required))
        XCTAssertTrue(capability.safeSetupLabels.contains(.highBandwidthRequired))
        XCTAssertTrue(capability.safeSetupLabels.contains(.useNaruHelperVideo))
    }

    func testActionRequestEncodesOnlyFixedLabelsAndIdentifier() throws {
        let runID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let request = ARDClassActionRequest(
            id: runID,
            actionKind: .restart,
            approvalState: .approved,
            capabilityStatus: .available,
            resultState: .sent
        )

        let data = try JSONEncoder().encode(request)
        let rendered = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(rendered.contains("restart"))
        XCTAssertTrue(rendered.contains("approved"))
        XCTAssertTrue(rendered.contains("available"))
        XCTAssertTrue(rendered.contains("sent"))
        XCTAssertFalse(rendered.contains("desk.tailnet.example"))
        XCTAssertFalse(rendered.contains("hunter2"))
        XCTAssertFalse(rendered.contains("rm -rf"))
        XCTAssertFalse(rendered.contains("/Users/example/private.png"))
    }

    func testSafeDiagnosticCapabilitiesDoNotEncodeUnsafeUserData() throws {
        let unsafeSentinels = [
            "desk.tailnet.example",
            "hunter2",
            "Secret message",
            "rm -rf",
            "user@example.com",
            "/Users/example/private.png"
        ]

        let data = try JSONEncoder().encode(AppleRemoteDesktopSupportCatalog.safeDiagnosticCapabilities)
        let rendered = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(rendered.contains(AppleRemoteDesktopCapabilityID.vncControlObserve.rawValue))
        XCTAssertTrue(rendered.contains(AppleRemoteDesktopCapabilityID.highPerformanceScreenSharing.rawValue))
        for sentinel in unsafeSentinels {
            XCTAssertFalse(rendered.contains(sentinel))
        }
    }
}
