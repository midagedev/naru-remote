import XCTest
import NaruHelperKit
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
        XCTAssertEqual(renderer.preparedCodecs, [.h264])
    }

    func testAcceptedStartPreparesRendererWithNegotiatedHEVCCodecBeforeFlush() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [1])
        let descriptor = HelperVideoStreamDescriptor(
            codec: .hevc,
            codecProfile: .main,
            frameRateBucket: .upTo15
        )
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

        XCTAssertTrue(outcome.startAccepted)
        XCTAssertEqual(renderer.preparedCodecs, [.hevc])
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertEqual(model.snapshot.helperVideoStreamDescriptor?.codec, .hevc)
    }

    func testEventStreamKeepsRenderingAccessUnitsAfterHealthySelection() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [1, 2, 3])
        let descriptor = HelperVideoStreamDescriptor(codecProfile: .high, frameRateBucket: .upTo30)
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(
                    descriptor: descriptor,
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe),
                        Self.accessUnit(sequence: 2, kind: .delta),
                        Self.accessUnit(sequence: 3, kind: .delta)
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
        XCTAssertEqual(outcome.receivedAccessUnitCount, 4)
        XCTAssertEqual(outcome.displayableFrameCount, 3)
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamDescriptor, descriptor)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertEqual(renderer.flushCount, 1)
        XCTAssertEqual(renderer.enqueuedSequences, [0, 1, 2, 3])
    }

    func testEventStreamDropsBackpressuredDeltaAccessUnitsButPreservesKeyframes() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1, 4],
            backpressuredSequences: [2, 3, 4]
        )
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .parameterSet),
                    Self.accessUnit(sequence: 1, kind: .keyframe),
                    Self.accessUnit(sequence: 2, kind: .delta),
                    Self.accessUnit(sequence: 3, kind: .delta),
                    Self.accessUnit(sequence: 4, kind: .keyframe)
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

        XCTAssertTrue(outcome.startAccepted)
        XCTAssertTrue(outcome.selectedVisualTransport)
        XCTAssertEqual(outcome.receivedAccessUnitCount, 5)
        XCTAssertEqual(outcome.displayableFrameCount, 2)
        XCTAssertEqual(outcome.droppedAccessUnitCount, 2)
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.sustainedUpdateBand, .usable)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.decodePressure, .medium)
        XCTAssertEqual(renderer.backpressureQuerySequences, [2])
        XCTAssertEqual(renderer.enqueuedSequences, [0, 1, 4])
    }

    func testFiniteStartDropsBackpressuredDeltaAccessUnitsBeforePreparingSampleBuffers() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1, 4],
            backpressuredSequences: [2, 3]
        )
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .parameterSet),
                    Self.accessUnit(sequence: 1, kind: .keyframe),
                    Self.accessUnit(sequence: 2, kind: .delta),
                    Self.accessUnit(sequence: 3, kind: .delta),
                    Self.accessUnit(sequence: 4, kind: .keyframe)
                ])
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )

        XCTAssertEqual(outcome.receivedAccessUnitCount, 5)
        XCTAssertEqual(outcome.displayableFrameCount, 2)
        XCTAssertEqual(outcome.droppedAccessUnitCount, 2)
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.sustainedUpdateBand, .usable)
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.decodePressure, .medium)
        XCTAssertEqual(renderer.backpressureQuerySequences, [2])
        XCTAssertEqual(renderer.enqueuedSequences, [0, 1, 4])
    }

    func testEventStreamBoundsRepeatedDeltaBackpressureQueriesUntilKeyframeRecovery() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1, 10],
            backpressuredSequences: [2, 9]
        )
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .parameterSet),
                    Self.accessUnit(sequence: 1, kind: .keyframe),
                    Self.accessUnit(sequence: 2, kind: .delta),
                    Self.accessUnit(sequence: 3, kind: .delta),
                    Self.accessUnit(sequence: 4, kind: .delta),
                    Self.accessUnit(sequence: 5, kind: .delta),
                    Self.accessUnit(sequence: 6, kind: .delta),
                    Self.accessUnit(sequence: 7, kind: .delta),
                    Self.accessUnit(sequence: 8, kind: .delta),
                    Self.accessUnit(sequence: 9, kind: .delta),
                    Self.accessUnit(sequence: 10, kind: .keyframe)
                ])
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )

        XCTAssertEqual(outcome.receivedAccessUnitCount, 11)
        XCTAssertEqual(outcome.displayableFrameCount, 2)
        XCTAssertEqual(outcome.droppedAccessUnitCount, 8)
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertEqual(renderer.backpressureQuerySequences, [2, 9])
        XCTAssertEqual(renderer.enqueuedSequences, [0, 1, 10])
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.sustainedUpdateBand, .usable)
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.decodePressure, .medium)
    }

    func testAsyncRendererPreparationYieldsMainActorDuringAccessUnitEnqueue() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let gate = HelperVideoRendererSuspensionGate()
        let renderer = SuspendingHelperVideoAccessUnitRenderer(gate: gate)
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                Self.startResult(accessUnits: [
                    Self.accessUnit(sequence: 0, kind: .keyframe)
                ])
            },
            renderer: renderer
        )

        let runnerTask = Task {
            await runner.start(
                sessionID: session.id,
                profileID: profile.id,
                model: model
            )
        }

        await gate.waitUntilSuspended()
        var mainActorProbeDidRun = false
        await Task { @MainActor in
            mainActorProbeDidRun = true
        }.value
        XCTAssertTrue(mainActorProbeDidRun)

        await gate.release()
        let outcome = await runnerTask.value

        XCTAssertEqual(outcome.displayableFrameCount, 1)
        XCTAssertEqual(renderer.enqueuedSequences, [0])
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

    #if canImport(Network)
    func testNetworkBackpressureStallFallsBackToVNCWithoutLosingSessionOrComposeDraft()
        async throws
    {
        let pairingSecret = "test-pairing-secret"
        let profileFingerprint = "sha256:helper-video"
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [0])
        let source = SessionBackpressuredAccessUnitSource(accessUnitsBeforeFailure: [
            NaruHelperVideoAccessUnit(
                sequence: 0,
                kind: .keyframe,
                binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
            )
        ])
        let server = try NaruHelperVideoStreamNetworkServer(
            pipeline: NaruHelperVideoStreamFramePipeline(
                requestHandler: NaruHelperVideoTransportRequestHandler(
                    expectedPairingSecret: pairingSecret,
                    expectedProfileFingerprint: profileFingerprint,
                    capabilityProvider: {
                        HelperVideoCapabilityResponseBody(
                            availability: .available,
                            screenRecordingPermission: .granted,
                            codecSupport: .h264,
                            latencyModes: [.lowLatency]
                        )
                    }
                ),
                accessUnitSource: source
            ),
            transportProtection: .authenticatedPrivateProfile
        )
        server.start()
        defer { server.cancel() }
        let port = try await Self.waitForPort(server)
        try await Task.sleep(for: .milliseconds(50))

        let runner = HelperVideoStreamSessionRunner(
            networkClient: HelperVideoStreamNetworkClient(
                host: "127.0.0.1",
                port: port,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret,
                transportProtection: .authenticatedPrivateProfile,
                timeout: 3
            ),
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
        XCTAssertEqual(outcome.receivedAccessUnitCount, 1)
        XCTAssertEqual(outcome.displayableFrameCount, 1)
        XCTAssertEqual(outcome.fallbackFailureCode, .streamStalled)
        XCTAssertEqual(outcome.fallbackStallReason, .transportBackpressure)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.session?.state, .active)
        XCTAssertEqual(snapshot.composeDraft?.text, "입력 유지")
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .fallbackToVNC)
        XCTAssertEqual(renderer.enqueuedSequences, [0])
        XCTAssertEqual(renderer.flushCount, 2)
    }
    #endif

    func testDecoderRejectionRequestsKeyframeAndKeepsLaneWhenSupportIsAdvertised() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1, 3, 4],
            throwingSequences: [2]
        )
        let recorder = KeyframeRequestRecorder()
        let descriptor = HelperVideoStreamDescriptor(
            codecProfile: .high,
            frameRateBucket: .upTo30,
            supportsKeyframeRequest: true
        )
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(
                    descriptor: descriptor,
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe),
                        Self.accessUnit(sequence: 2, kind: .delta),
                        Self.accessUnit(sequence: 3, kind: .keyframe),
                        Self.accessUnit(sequence: 4, kind: .delta)
                    ],
                    requestKeyframe: { reason in
                        recorder.record(reason)
                    }
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

        XCTAssertEqual(recorder.reasons, [.decoderRecovery])
        XCTAssertNil(outcome.fallbackFailureCode)
        XCTAssertTrue(outcome.selectedVisualTransport)
        XCTAssertEqual(outcome.displayableFrameCount, 3)
        XCTAssertEqual(snapshot.visualTransportMode, .helperVideo)
        XCTAssertEqual(snapshot.helperVideoStreamHealth.state, .healthy)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .available)
        XCTAssertNil(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode)
    }

    func testDecoderRejectionFallsBackWhenKeyframeRequestIsUnsupported() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1, 3, 4],
            throwingSequences: [2]
        )
        let recorder = KeyframeRequestRecorder()
        let descriptor = HelperVideoStreamDescriptor(
            codecProfile: .high,
            frameRateBucket: .upTo30,
            supportsKeyframeRequest: false
        )
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(
                    descriptor: descriptor,
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe),
                        Self.accessUnit(sequence: 2, kind: .delta),
                        Self.accessUnit(sequence: 3, kind: .keyframe),
                        Self.accessUnit(sequence: 4, kind: .delta)
                    ],
                    requestKeyframe: { reason in
                        recorder.record(reason)
                    }
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

        XCTAssertTrue(recorder.reasons.isEmpty)
        XCTAssertEqual(outcome.fallbackFailureCode, .decoderRejected)
        XCTAssertEqual(outcome.displayableFrameCount, 1)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.lastFailureCode, .decoderRejected)
    }

    func testRecoveryBudgetExhaustionFallsBackWithoutADisplayableFrame() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(
            displayableSequences: [1],
            throwingSequences: [2]
        )
        let recorder = KeyframeRequestRecorder()
        let recoveredUnits = (3..<(3 + HelperVideoKeyframeRecoveryPolicy.recoveryBudgetAccessUnits))
            .map { Self.accessUnit(sequence: $0, kind: .delta) }
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(
                    descriptor: HelperVideoStreamDescriptor(supportsKeyframeRequest: true),
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe),
                        Self.accessUnit(sequence: 2, kind: .delta)
                    ] + recoveredUnits,
                    requestKeyframe: { reason in
                        recorder.record(reason)
                    }
                )
            },
            renderer: renderer
        )

        let outcome = await runner.start(
            sessionID: session.id,
            profileID: profile.id,
            model: model
        )

        XCTAssertEqual(recorder.reasons, [.decoderRecovery])
        XCTAssertEqual(outcome.fallbackFailureCode, .decoderRejected)
        XCTAssertEqual(outcome.displayableFrameCount, 1)
        XCTAssertEqual(
            model.snapshot.helperVideoProfileState[profile.id]?.lastFailureCode,
            .decoderRejected
        )
    }

    func testStreamStallStaysTerminalEvenWhenKeyframeRequestIsAvailable() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer(displayableSequences: [1])
        let recorder = KeyframeRequestRecorder()
        let runner = HelperVideoStreamSessionRunner(
            eventStream: { _ in
                Self.eventStream(
                    descriptor: HelperVideoStreamDescriptor(supportsKeyframeRequest: true),
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe)
                    ],
                    requestKeyframe: { reason in
                        recorder.record(reason)
                    },
                    stall: HelperVideoWireEnvelope(
                        messageType: .streamStalled,
                        profileFingerprint: "sha256:helper-video",
                        body: HelperVideoStreamStallBody(reason: .encoderUnavailable)
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

        XCTAssertTrue(recorder.reasons.isEmpty)
        XCTAssertEqual(outcome.fallbackFailureCode, .streamStalled)
        XCTAssertEqual(outcome.fallbackStallReason, .encoderUnavailable)
        XCTAssertEqual(model.snapshot.visualTransportMode, .vncFramebuffer)
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

    func testTransportProtectionFailureRecordsSafeFailureWithoutLeakingRawError() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = Self.model(profile: profile, session: session)
        let renderer = FakeHelperVideoAccessUnitRenderer()
        let runner = HelperVideoStreamSessionRunner(
            startStream: { _, _ in
                throw HelperVideoStreamNetworkClientError.transportProtectionRequired
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
        XCTAssertEqual(outcome.fallbackFailureCode, .transportProtectionRequired)
        XCTAssertEqual(snapshot.visualTransportMode, .vncFramebuffer)
        XCTAssertEqual(snapshot.helperVideoProfileState[profile.id]?.availability, .unreachable)
        XCTAssertEqual(
            snapshot.helperVideoProfileState[profile.id]?.lastFailureCode,
            .transportProtectionRequired
        )
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

    private nonisolated static func startResult(
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

    private nonisolated static func eventStream(
        descriptor: HelperVideoStreamDescriptor = HelperVideoStreamDescriptor(),
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>],
        requestKeyframe: (@Sendable (HelperVideoKeyframeRequestReason) -> Void)? = nil,
        stall: HelperVideoWireEnvelope<HelperVideoStreamStallBody>? = nil
    ) -> HelperVideoStreamNetworkEvents {
        HelperVideoStreamNetworkEvents(requestKeyframe: requestKeyframe) { continuation in
            continuation.yield(.startResponse(
                HelperVideoWireEnvelope(
                    messageType: .startStream,
                    profileFingerprint: "sha256:helper-video",
                    body: HelperVideoStartStreamResponseBody(
                        result: .accepted,
                        streamDescriptor: descriptor
                    )
                )
            ))
            for accessUnit in accessUnits {
                continuation.yield(.accessUnit(accessUnit))
            }
            if let stall {
                continuation.yield(.stall(stall))
            }
            continuation.finish()
        }
    }

    private nonisolated static func accessUnit(
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

    #if canImport(Network)
    private nonisolated static func waitForPort(
        _ server: NaruHelperVideoStreamNetworkServer
    ) async throws -> UInt16 {
        for _ in 0..<50 {
            if let port = server.port, port > 0 {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(server.port)
    }
    #endif
}

#if canImport(Network)
private struct SessionBackpressuredAccessUnitSource: NaruHelperVideoAccessUnitSource {
    var accessUnitsBeforeFailure: [NaruHelperVideoAccessUnit]

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        accessUnitsBeforeFailure
    }

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let accessUnitsBeforeFailure = accessUnitsBeforeFailure
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnitsBeforeFailure {
                continuation.yield(accessUnit)
            }
            continuation.finish(
                throwing: NaruHelperVideoToolboxSyntheticAccessUnitSourceError
                    .encodedAccessUnitBackpressureExceeded
            )
        }
    }
}
#endif

@MainActor
private final class FakeHelperVideoAccessUnitRenderer: HelperVideoAccessUnitRendering, HelperVideoAccessUnitRenderBackpressureReporting {
    private let displayableSequences: Set<Int>
    private let throwingSequences: Set<Int>
    private let backpressuredSequences: Set<Int>

    private(set) var enqueuedSequences: [Int] = []
    private(set) var backpressureQuerySequences: [Int] = []
    private(set) var flushCount = 0
    private(set) var preparedCodecs: [HelperVideoCodec] = []

    init(
        displayableSequences: Set<Int> = [],
        throwingSequences: Set<Int> = [],
        backpressuredSequences: Set<Int> = []
    ) {
        self.displayableSequences = displayableSequences
        self.throwingSequences = throwingSequences
        self.backpressuredSequences = backpressuredSequences
    }

    func shouldDropAccessUnitForBackpressure(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) -> Bool {
        let body = decoded.envelope.body
        backpressureQuerySequences.append(body.sequence)
        return body.kind == .delta && backpressuredSequences.contains(body.sequence)
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        let sequence = decoded.envelope.body.sequence
        enqueuedSequences.append(sequence)
        if throwingSequences.contains(sequence) {
            throw FakeHelperVideoRendererError.decoderRejected
        }
        return displayableSequences.contains(sequence)
    }

    func flush() async {
        flushCount += 1
    }

    func prepare(codec: HelperVideoCodec) async {
        preparedCodecs.append(codec)
    }
}

@MainActor
private final class SuspendingHelperVideoAccessUnitRenderer: HelperVideoAccessUnitRendering {
    private let gate: HelperVideoRendererSuspensionGate

    private(set) var enqueuedSequences: [Int] = []

    init(gate: HelperVideoRendererSuspensionGate) {
        self.gate = gate
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        enqueuedSequences.append(decoded.envelope.body.sequence)
        await gate.suspendUntilReleased()
        return true
    }

    func flush() async {}
}

private actor HelperVideoRendererSuspensionGate {
    private var didSuspend = false
    private var isReleased = false
    private var suspendedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendUntilReleased() async {
        didSuspend = true
        let waiters = suspendedWaiters
        suspendedWaiters.removeAll()
        waiters.forEach { $0.resume() }

        guard !isReleased else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilSuspended() async {
        guard !didSuspend else {
            return
        }
        await withCheckedContinuation { continuation in
            suspendedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private enum FakeHelperVideoRendererError: Error {
    case decoderRejected
}

private final class KeyframeRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HelperVideoKeyframeRequestReason] = []

    func record(_ reason: HelperVideoKeyframeRequestReason) {
        lock.lock()
        recorded.append(reason)
        lock.unlock()
    }

    var reasons: [HelperVideoKeyframeRequestReason] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
