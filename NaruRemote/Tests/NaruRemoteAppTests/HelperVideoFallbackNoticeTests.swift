import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

// Contract ↔ assertion table (spec 042 Round B; FR-004, FR-005, FR-010).
//
// | Contract clause                                                | Test |
// | ---------------------------------------------------------------- | ---- |
// | FR-005: permissionMissing start refusal sets the catalog notice  | testPermissionMissingStartSetsFallbackNoticeOnce (integration through connect + rejected start response, SC-4 shape) |
// | FR-005: notice appears at most once per sessionID                | testPermissionMissingStartSetsFallbackNoticeOnce (dismiss + second refusal stays nil) and testMidSessionFallbackArmsStreamStalledNoticeOncePerSession |
// | FR-005: a new session is eligible again                          | testNoticeReArmsForNewSessionAfterReconnect |
// | FR-005: mid-session fallback reason is streamStalled             | testMidSessionFallbackArmsStreamStalledNoticeOncePerSession |
// | FR-005: helperVideo == nil / isEnabled == false / isRevoked == true ⇒ never | testStartRefusalWithoutHelperConfigurationProducesNoNotice, testStartRefusalWithDisabledHelperVideoProducesNoNotice, testStartRefusalWithRevokedHelperVideoProducesNoNotice, testMidSessionFallbackWithoutHelperConfigurationProducesNoNotice, testMidSessionFallbackWithDisabledHelperVideoProducesNoNotice, testMidSessionFallbackWithRevokedHelperVideoProducesNoNotice |
// | FR-005: reason comes from the fixed catalog, exact titles        | testNoticeCatalogMapsEveryFailureCodeAndTitlesAreFixed |
// | FR-005: dismissal clears the notice but not the latch            | testDismissClearsNoticeAndLatchKeepsSessionFromReArming |
// | FR-005: a refusal after the session ended arms nothing           | testRefusalAfterSessionClosedProducesNoNotice |
// | FR-005: a refusal for a profile that is not the active session's arms nothing | testStartRefusalForOtherProfileProducesNoNotice |
// | FR-004: marker follows visualTransportMode (helperVideo only)    | testMarkerFollowsVisualTransportModeSnapshotField |
// | FR-010: titles contain no interpolated user content              | testNoticeCatalogMapsEveryFailureCodeAndTitlesAreFixed asserts exact literals; the round's grep gate asserts no `\(` inside any title line |
@MainActor
final class HelperVideoFallbackNoticeTests: XCTestCase {

    // MARK: - FAIL-first (T-B2): the notice is nil today after a
    // permissionMissing start. Driven through the real bootstrap
    // (connect → start stream rejected with safeFailureCode
    // .permissionMissing), the founder's measured 2026-09-06 scenario.

    func testPermissionMissingStartSetsFallbackNoticeOnce() async throws {
        let fixture = Self.makeConnectedModelWithRefusedHelperVideoStart(
            failureCode: .permissionMissing
        )
        await fixture.model.connectSelectedProfile()

        try await Self.settle {
            fixture.model.snapshot.helperVideoProfileState[fixture.profileID]?
                .availability != .permissionMissing
        }

        XCTAssertEqual(
            fixture.model.snapshot.helperVideoFallbackNotice,
            .permissionMissing,
            "A refused helper-video start must surface the one-line catalog notice."
        )
        XCTAssertEqual(
            fixture.model.snapshot.helperVideoFallbackNotice?.title,
            "Helper video off — Mac needs Screen Recording permission"
        )
        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)

        fixture.model.dismissHelperVideoFallbackNotice()
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)

        // Second refusal in the SAME session must not re-arm the notice.
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "The latch must keep a second fallback in one session silent."
        )
    }

    // MARK: - Catalog mapping (FR-005, FR-010)

    func testNoticeCatalogMapsEveryFailureCodeAndTitlesAreFixed() {
        let expectedTitles: [HelperVideoFallbackNotice: String] = [
            .permissionMissing: "Helper video off — Mac needs Screen Recording permission",
            .helperUnreachable: "Helper video off — Naru Helper not reachable",
            .streamStalled: "Helper video off — stream stalled, showing VNC",
            .revoked: "Helper video off — pairing revoked on the Mac",
            .codecUnsupported: "Helper video off — codec not supported",
            .privateNetworkRequired: "Helper video off — private network required",
            .other: "Helper video off — showing VNC"
        ]
        XCTAssertEqual(
            Set(HelperVideoFallbackNotice.allCases),
            Set(expectedTitles.keys),
            "Every catalog case must carry a fixed title."
        )
        for notice in HelperVideoFallbackNotice.allCases {
            XCTAssertEqual(notice.title, expectedTitles[notice])
        }

        let expectedMapping: [HelperVideoFailureCode: HelperVideoFallbackNotice] = [
            .permissionMissing: .permissionMissing,
            .transportFailed: .helperUnreachable,
            .transportProtectionRequired: .helperUnreachable,
            .streamStalled: .streamStalled,
            .fallbackToVNC: .streamStalled,
            .revoked: .revoked,
            .codecUnsupported: .codecUnsupported,
            .privateNetworkRequired: .privateNetworkRequired,
            .notConfigured: .other,
            .disabled: .other,
            .authFailed: .other,
            .decoderRejected: .other
        ]
        XCTAssertEqual(
            HelperVideoFailureCode.allCases.count,
            expectedMapping.count,
            "The mapping must be exhaustive over HelperVideoFailureCode."
        )
        for code in HelperVideoFailureCode.allCases {
            XCTAssertEqual(
                HelperVideoFallbackNotice.notice(for: code),
                expectedMapping[code],
                "Catalog mapping diverged for \(code.rawValue)."
            )
        }
        for notice in HelperVideoFallbackNotice.allCases {
            XCTAssertFalse(
                notice.title.contains("("),
                "Titles are fixed catalog words; dynamic content is forbidden (constitution §IV)."
            )
        }
    }

    // MARK: - Start refusal × profile matrix (FR-005)

    func testStartRefusalWithoutHelperConfigurationProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(helperVideoConfiguration: nil)
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "A profile without helper video config never gets a notice."
        )
    }

    func testStartRefusalWithDisabledHelperVideoProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: false,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "A profile with helper video disabled never gets a notice."
        )
    }

    func testStartRefusalWithRevokedHelperVideoProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                isRevoked: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "A revoked pairing never gets a notice."
        )
    }

    func testStartRefusalForOtherProfileProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let otherProfile = try ConnectionProfile(
            displayName: "Other",
            host: "other.tailnet.ts.net"
        )
        fixture.model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:other",
                availability: .permissionMissing,
                lastFailureCode: .permissionMissing,
                lastCheckedBucket: .recent
            ),
            for: otherProfile.id
        )

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "A refusal for a profile other than the active session's arms nothing."
        )
    }

    // MARK: - Mid-session fallback (FR-005, FR-004)

    func testMidSessionFallbackArmsStreamStalledNoticeOncePerSession() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        XCTAssertEqual(
            fixture.model.snapshot.visualTransportMode,
            .helperVideo,
            "Marker shows while helper video carries frames (FR-004)."
        )
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)

        Self.stallHelperVideo(on: fixture.model)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(
            fixture.model.snapshot.helperVideoFallbackNotice,
            .streamStalled,
            "A mid-session fallback must announce the catalog stream-stalled reason."
        )
        XCTAssertEqual(
            fixture.model.snapshot.helperVideoFallbackNotice?.title,
            "Helper video off — stream stalled, showing VNC"
        )

        fixture.model.dismissHelperVideoFallbackNotice()
        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        Self.stallHelperVideo(on: fixture.model)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "A second fallback in the same session must not re-arm the notice."
        )
    }

    func testMidSessionFallbackWithoutHelperConfigurationProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(helperVideoConfiguration: nil)
        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        Self.stallHelperVideo(on: fixture.model)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)
    }

    func testMidSessionFallbackWithDisabledHelperVideoProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: false,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        Self.stallHelperVideo(on: fixture.model)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)
    }

    func testMidSessionFallbackWithRevokedHelperVideoProducesNoNotice() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                isRevoked: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        Self.stallHelperVideo(on: fixture.model)

        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)
    }

    // MARK: - Dismissal and session lifecycle

    func testDismissClearsNoticeAndLatchKeepsSessionFromReArming() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)
        XCTAssertEqual(fixture.model.snapshot.helperVideoFallbackNotice, .permissionMissing)

        fixture.model.dismissHelperVideoFallbackNotice()
        XCTAssertNil(fixture.model.snapshot.helperVideoFallbackNotice)

        Self.stallHelperVideo(on: fixture.model)
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "Dismissal is final for the session; only a new session re-arms."
        )
        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
    }

    func testRefusalAfterSessionClosedProducesNoNotice() throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let session = RemoteSession(profileID: profile.id, state: .closed)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session
            )
        )
        Self.refuseHelperVideoStart(on: model, profileID: profile.id)

        XCTAssertEqual(model.snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(
            model.snapshot.helperVideoFallbackNotice,
            "A late refusal after the session ended must not surface a notice."
        )
    }

    func testNoticeReArmsForNewSessionAfterReconnect() async throws {
        let fixture = Self.makeConnectedModelWithRefusedHelperVideoStart(
            failureCode: .permissionMissing
        )
        await fixture.model.connectSelectedProfile()
        try await Self.settle {
            fixture.model.snapshot.helperVideoProfileState[fixture.profileID]?
                .availability != .permissionMissing
        }
        XCTAssertEqual(fixture.model.snapshot.helperVideoFallbackNotice, .permissionMissing)

        // A fresh connect creates a new session and resets transport state;
        // the notice and its latch must not carry over.
        await fixture.model.connectSelectedProfile()
        XCTAssertNil(
            fixture.model.snapshot.helperVideoFallbackNotice,
            "resetVisualTransportState clears the notice with the old session."
        )

        // The same refusal in the NEW session is announced again. (The
        // bootstrap itself is not retried within one model instance once the
        // profile availability latched .permissionMissing — existing
        // behavior — so the refusal is driven the same way the runner
        // delivers it: a session-scoped profile-state failure.)
        Self.refuseHelperVideoStart(on: fixture.model, profileID: fixture.profileID)
        XCTAssertEqual(
            fixture.model.snapshot.helperVideoFallbackNotice,
            .permissionMissing,
            "A new session must be eligible for the notice again."
        )
    }

    // MARK: - Marker derivation (FR-004)

    func testMarkerFollowsVisualTransportModeSnapshotField() throws {
        let fixture = Self.makeSnapshotDrivenFixture(
            helperVideoConfiguration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        XCTAssertEqual(
            fixture.model.snapshot.visualTransportMode,
            .vncFramebuffer,
            "VNC sessions render no marker; the shell derives the input from this field."
        )

        Self.makeHelperVideoLive(on: fixture.model, profileID: fixture.profileID)
        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .helperVideo)

        Self.stallHelperVideo(on: fixture.model)
        XCTAssertEqual(fixture.model.snapshot.visualTransportMode, .vncFramebuffer)
    }

    // MARK: - Fixtures

    private struct ModelFixture {
        let model: NaruRemoteAppModel
        let profileID: ConnectionProfile.ID
    }

    /// Builds a model with an ACTIVE session whose profile carries the given
    /// helper-video configuration (mirrors the snapshot-driven fixture style
    /// of `NaruRemoteAppModelTests`).
    private static func makeSnapshotDrivenFixture(
        helperVideoConfiguration: HelperVideoConnectionConfiguration?,
        sessionState: RemoteSessionState = .active
    ) -> ModelFixture {
        let profile: ConnectionProfile
        if let helperVideoConfiguration {
            profile = (try? ConnectionProfile(
                displayName: "Desk",
                host: "desk.tailnet.ts.net",
                helperVideo: helperVideoConfiguration
            ))!
        } else {
            profile = (try? ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net"))!
        }
        let session = RemoteSession(
            profileID: profile.id,
            state: sessionState,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session
            )
        )
        return ModelFixture(model: model, profileID: profile.id)
    }

    /// Simulates a refused helper-video start: the runner's
    /// `markProfileFailure` path lands in `setHelperVideoProfileState`
    /// with the true failure code while the transport is still VNC.
    private static func refuseHelperVideoStart(
        on model: NaruRemoteAppModel,
        profileID: ConnectionProfile.ID
    ) {
        model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video",
                availability: .permissionMissing,
                lastFailureCode: .permissionMissing,
                lastCheckedBucket: .recent
            ),
            for: profileID
        )
    }

    /// Selects helper video as the live visual transport.
    private static func makeHelperVideoLive(
        on model: NaruRemoteAppModel,
        profileID: ConnectionProfile.ID
    ) {
        model.setHelperVideoProfileState(
            HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video",
                availability: .available,
                lastCheckedBucket: .recent
            ),
            for: profileID
        )
        XCTAssertTrue(model.selectHelperVideoVisualTransport(
            health: HelperVideoStreamHealth(state: .healthy, sustainedUpdateBand: .smooth)
        ))
    }

    /// Drives the mid-session health-driven fallback to VNC.
    private static func stallHelperVideo(on model: NaruRemoteAppModel) {
        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            )
        )
    }

    /// Full bootstrap path: connect succeeds over VNC while the helper-video
    /// start stream is rejected with the given failure code.
    private static func makeConnectedModelWithRefusedHelperVideoStart(
        failureCode: HelperVideoFailureCode
    ) -> ModelFixture {
        let profile = (try? ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        ))!
        let connector = FallbackNoticeFirstFrameConnector(width: 2, height: 1, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: ["helper-video-token:desk": "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperVideoStartStream: { _, _, _, _, _ in
                Self.rejectedStartResult(failureCode: failureCode)
            }
        )
        return ModelFixture(model: model, profileID: profile.id)
    }

    private nonisolated static func rejectedStartResult(
        failureCode: HelperVideoFailureCode
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoStartStreamResponseBody(
                    result: .rejected,
                    streamDescriptor: HelperVideoStreamDescriptor(),
                    safeFailureCode: failureCode
                )
            ),
            accessUnits: []
        )
    }

    /// Polls until `isPending` stops holding, failing on timeout (same
    /// contract as `NaruRemoteAppModelTests.settle`).
    private static func settle(
        while isPending: () -> Bool,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if !isPending() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard !isPending() else {
            XCTFail("Timed out after \(timeout) waiting for the awaited state")
            return
        }
    }
}

/// Minimal first-frame connector for the bootstrap-path tests. The shared
/// `FakeFirstFrameConnector` in `NaruRemoteAppModelTests.swift` is
/// file-private, so this follows its pattern with only the members the
/// notice tests exercise (connect + clipboard no-ops).
private final class FallbackNoticeFirstFrameConnector:
    RFBAuthenticatedFirstFrameConnecting, RemoteClipboardTextClient
{
    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? { RFBFrameMetadata(width: width, height: height) }
    let utf8ClipboardSupport: RemoteClipboardUTF8Support = .unknown

    private let width: Int
    private let height: Int
    private let name: String

    init(width: Int, height: Int, name: String) {
        self.width = width
        self.height = height
        self.name = name
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(
            host: host,
            port: port,
            credential: .none,
            timeout: timeout
        )
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func setClipboardText(_ text: String) throws {}

    func sendPasteCommand(_ command: PasteCommand) throws {}
}
