import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class HelperVideoStreamSessionRunnerTests: XCTestCase {
    func testAcceptedStartSelectsHelperVideoAndMarksHealthyAfterDisplayableFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [1])
        let descriptor = HelperVideoStreamDescriptor(codecProfile: .baseline, frameRateBucket: .upTo15)
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(
                    descriptor: descriptor,
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe)
                    ]
                )
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertTrue(outcome.startAccepted)
        XCTAssertTrue(outcome.selectedVisualTransport)
        XCTAssertEqual(outcome.receivedAccessUnitCount, 2)
        XCTAssertEqual(outcome.displayableFrameCount, 1)
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor, descriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.sustainedUpdateBand, .smooth)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode)
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertEqual(renderer.enqueuedSequences, [0, 1])
    }

    func testAcceptedStartDoesNotSelectHelperVideoForStaleSessionCallback() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let currentSession = RemoteSession(profileID: profile.id, state: .active)
        let staleSessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let model = Self.model(profile: profile, session: currentSession)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [0])
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .keyframe)
                ])
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: staleSessionID,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertTrue(outcome.startAccepted)
        XCTAssertFalse(outcome.selectedVisualTransport)
        XCTAssertEqual(outcome.fallbackFailureCode, .fallbackToVNC)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .idle)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode)
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertTrue(renderer.enqueuedSequences.isEmpty)
    }

    func testRejectedStartDoesNotMutateStaleSessionCallback() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let currentSession = RemoteSession(profileID: profile.id, state: .active)
        let staleSessionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let model = Self.model(profile: profile, session: currentSession)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(
                    result: .rejected,
                    safeFailureCode: .permissionMissing
                )
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: staleSessionID,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertFalse(outcome.startAccepted)
        XCTAssertEqual(outcome.fallbackFailureCode, .permissionMissing)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .idle)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode)
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertTrue(renderer.enqueuedSequences.isEmpty)
    }

    func testAcceptedStartFallsBackWhenHelperReportsStall() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(
                    accessUnits: [],
                    stall: HelperVideoWireEnvelope(
                        messageType: .streamStalled,
                        profileFingerprint: "sha256:helper-video",
                        body: HelperVideoStreamStallBody(
                            reason: .noAccessUnit,
                            health: HelperVideoStreamHealth(
                                state: .stalled,
                                startupBand: .failed,
                                sustainedUpdateBand: .stalled,
                                fallbackCountBucket: .one
                            )
                        )
                    )
                )
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertEqual(outcome.fallbackFailureCode, .streamStalled)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.sustainedUpdateBand, .stalled)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .failed)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .streamStalled)
        XCTAssertEqual(renderer.flushCount, 2)
    }

    func testDecoderRejectionFlushesAndFallsBackWithoutDroppingSession() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [0],
            throwingSequences: [0]
        )
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .keyframe)
                ])
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertEqual(outcome.fallbackFailureCode, .decoderRejected)
        XCTAssertEqual(outcome.displayableFrameCount, 0)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.decodePressure, .high)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .failed)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .decoderRejected)
        XCTAssertEqual(renderer.flushCount, 2)
    }

    func testRejectedStartRecordsSafeFailureWithoutSelectingHelperVideo() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(
                    result: .rejected,
                    safeFailureCode: .permissionMissing
                )
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertFalse(outcome.startAccepted)
        XCTAssertFalse(outcome.selectedVisualTransport)
        XCTAssertEqual(outcome.fallbackFailureCode, .permissionMissing)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .permissionMissing)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .permissionMissing)
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertTrue(renderer.enqueuedSequences.isEmpty)
    }

    func testNetworkFailureRecordsTransportFailureWithoutLeakingRawError() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                throw HelperVideoStreamNetworkClientError.timedOut
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertFalse(outcome.startAccepted)
        XCTAssertEqual(outcome.fallbackFailureCode, .transportFailed)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .unreachable)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .transportFailed)
        XCTAssertNil(snapshot.session?.lastError)
        XCTAssertEqual(renderer.flushCount, 1)
    }

    func testNetworkFailureDoesNotMutateStaleSessionCallback() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let currentSession = RemoteSession(profileID: profile.id, state: .active)
        let staleSessionID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let model = Self.model(profile: profile, session: currentSession)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                throw HelperVideoStreamNetworkClientError.timedOut
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: staleSessionID,
            profileID: profile.id,
            model: model
        )
        let snapshot = model.snapshot

        XCTAssertFalse(outcome.startAccepted)
        XCTAssertEqual(outcome.fallbackFailureCode, .transportFailed)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertNil(snapshot.helperVideoStreamDescriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .idle)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode)
        XCTAssertEqual(renderer.flushCount, 1)
    }

    private static func model(
        profile: ConnectionProfile,
        session: RemoteSession
    ) -> NaruRemoteAppModel {
        NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "입력 유지"),
                helperVideoProfileState: [
                    profile.id: HelperVideoProfileState(
                        isEnabled: true,
                        pairingFingerprint: "sha256:helper-video",
                        availability: .available,
                        lastCheckedBucket: .recent
                    )
                ]
            )
        )
    }

    private static func startResult(
        result: HelperVideoStartStreamResult = .accepted,
        descriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(),
        safeFailureCode: HelperVideoFailureCode? = nil,
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = [],
        stall: HelperVideoWireEnvelope<HelperVideoStreamStallBody>? = nil
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoStartStreamResponseBody(
                    result: result,
                    streamDescriptor: descriptor,
                    safeFailureCode: safeFailureCode
                )
            ),
            accessUnits: accessUnits,
            stall: stall
        )
    }

    private static func accessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
            ),
            binaryPayload: Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
        )
    }
}

@MainActor
private final class FakeHelperVideoAccessUnitRenderer: HelperVideoAccessUnitRendering {
    private let displayableSequences: Set<Int>
    private let throwingSequences: Set<Int>

    private(set) var enqueuedSequences: [Int] = []
    private(set) var flushCount = 0

    init(
        displayableSequences: Set<Int> = [],
        throwingSequences: Set<Int> = []
    ) {
        self.displayableSequences = displayableSequences
        self.throwingSequences = throwingSequences
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> Bool {
        let sequence = decoded.envelope.body.sequence
        enqueuedSequences.append(sequence)
        if throwingSequences.contains(sequence) {
            throw FakeHelperVideoRendererError.decoderRejected
        }
        return displayableSequences.contains(sequence)
    }

    func flush() {
        flushCount += 1
    }
}

private enum FakeHelperVideoRendererError: Error {
    case decoderRejected
}
