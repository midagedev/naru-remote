import Foundation
import NaruRemoteCore

@MainActor
public protocol HelperVideoAccessUnitRendering: AnyObject {
    @discardableResult
    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool

    func flush() async
}

@MainActor
public protocol HelperVideoAccessUnitRenderBackpressureReporting: AnyObject {
    func shouldDropAccessUnitForBackpressure(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) -> Bool
}

// @unchecked Sendable justified: the wrapped renderer remains main-actor
// isolated for every operation. The non-MainActor runner may hold and pass this
// box across tasks, but the box exposes no nonisolated access to the renderer.
private final class HelperVideoMainActorRendererBox: @unchecked Sendable {
    private let renderer: any HelperVideoAccessUnitRendering

    init(_ renderer: any HelperVideoAccessUnitRendering) {
        self.renderer = renderer
    }

    @MainActor
    @discardableResult
    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        try await renderer.enqueueDisplayableAccessUnit(decoded)
    }

    @MainActor
    func shouldDropAccessUnitForBackpressure(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) -> Bool {
        guard let backpressureReporter = renderer as? any HelperVideoAccessUnitRenderBackpressureReporting else {
            return false
        }
        return backpressureReporter.shouldDropAccessUnitForBackpressure(decoded)
    }

    @MainActor
    func flush() async {
        await renderer.flush()
    }
}

public struct HelperVideoStreamSessionOutcome: Equatable, Sendable {
    public var startAccepted: Bool
    public var selectedVisualTransport: Bool
    public var receivedAccessUnitCount: Int
    public var displayableFrameCount: Int
    public var droppedAccessUnitCount: Int
    public var fallbackFailureCode: HelperVideoFailureCode?
    public var fallbackStallReason: HelperVideoStreamStallReason?
    public var finalHealth: HelperVideoStreamHealth

    public init(
        startAccepted: Bool,
        selectedVisualTransport: Bool,
        receivedAccessUnitCount: Int,
        displayableFrameCount: Int,
        droppedAccessUnitCount: Int = 0,
        fallbackFailureCode: HelperVideoFailureCode? = nil,
        finalHealth: HelperVideoStreamHealth,
        fallbackStallReason: HelperVideoStreamStallReason? = nil
    ) {
        self.startAccepted = startAccepted
        self.selectedVisualTransport = selectedVisualTransport
        self.receivedAccessUnitCount = max(receivedAccessUnitCount, 0)
        self.displayableFrameCount = max(displayableFrameCount, 0)
        self.droppedAccessUnitCount = max(droppedAccessUnitCount, 0)
        self.fallbackFailureCode = fallbackFailureCode
        self.fallbackStallReason = fallbackStallReason
        self.finalHealth = finalHealth
    }
}

private enum HelperVideoAccessUnitRenderResult: Equatable, Sendable {
    case notDisplayable
    case displayable
    case droppedForBackpressure
}

// @unchecked Sendable justified: the runner stores immutable configuration
// (`startStream`, `maxServerFrames`) plus `HelperVideoMainActorRendererBox`.
// Network start/result handling may run off MainActor, while all renderer and
// app-model mutation still happens through explicit actor hops.
public final class HelperVideoStreamSessionRunner: @unchecked Sendable {
    public typealias StartStream = @Sendable (
        HelperVideoStartStreamRequestBody,
        Int
    ) async throws -> HelperVideoStreamNetworkStartResult
    public typealias EventStream = @Sendable (
        HelperVideoStartStreamRequestBody
    ) -> HelperVideoStreamNetworkEvents

    private let startStream: StartStream?
    private let eventStream: EventStream?
    private let renderer: HelperVideoMainActorRendererBox
    private let maxServerFrames: Int

    public init(
        startStream: @escaping StartStream,
        renderer: any HelperVideoAccessUnitRendering,
        maxServerFrames: Int = 16
    ) {
        self.startStream = startStream
        self.eventStream = nil
        self.renderer = HelperVideoMainActorRendererBox(renderer)
        self.maxServerFrames = max(maxServerFrames, 1)
    }

    public init(
        eventStream: @escaping EventStream,
        renderer: any HelperVideoAccessUnitRendering,
        maxServerFrames: Int = 16
    ) {
        self.startStream = nil
        self.eventStream = eventStream
        self.renderer = HelperVideoMainActorRendererBox(renderer)
        self.maxServerFrames = max(maxServerFrames, 1)
    }

    #if canImport(Network)
    public convenience init(
        networkClient: HelperVideoStreamNetworkClient,
        renderer: any HelperVideoAccessUnitRendering,
        maxServerFrames: Int = 16
    ) {
        self.init(
            eventStream: { requestBody in
                networkClient.streamEvents(requestBody)
            },
            renderer: renderer,
            maxServerFrames: maxServerFrames
        )
    }
    #endif

    public func start(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel,
        requestBody: HelperVideoStartStreamRequestBody = HelperVideoStartStreamRequestBody()
    ) async -> HelperVideoStreamSessionOutcome {
        if let eventStream {
            return await startEventStream(
                eventStream(requestBody),
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        guard let startStream else {
            return await failBeforeStart(
                failureCode: .transportFailed,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        let result: HelperVideoStreamNetworkStartResult
        do {
            result = try await startStream(requestBody, maxServerFrames)
        } catch {
            let failureCode = helperVideoFailureCode(for: error, startAccepted: false)
            guard await isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return await ignoreStaleResult(
                    startAccepted: false,
                    receivedAccessUnitCount: 0,
                    fallbackFailureCode: failureCode,
                    model: model
                )
            }
            return await failBeforeStart(
                failureCode: failureCode,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        return await handleStartResult(
            result,
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )
    }

    private func startEventStream(
        _ events: HelperVideoStreamNetworkEvents,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async -> HelperVideoStreamSessionOutcome {
        var startAccepted = false
        var selectedVisualTransport = false
        var receivedAccessUnitCount = 0
        var displayableFrameCount = 0
        var droppedAccessUnitCount = 0
        var didPublishHealthy = false
        var didPublishBackpressureHealth = false
        var renderBackpressureGate = HelperVideoRenderBackpressureGate()
        var recoveryPolicy = HelperVideoKeyframeRecoveryPolicy()
        var supportsKeyframeRequest = false
        let requestKeyframe = events.requestKeyframe

        do {
            for try await event in events {
                guard await isCurrentSession(
                    sessionID: sessionID,
                    profileID: profileID,
                    model: model
                ) else {
                    return await ignoreStaleResult(
                        startAccepted: startAccepted,
                        receivedAccessUnitCount: receivedAccessUnitCount,
                        fallbackFailureCode: .fallbackToVNC,
                        model: model
                    )
                }

                switch event {
                case .startResponse(let response):
                    guard response.body.result == .accepted else {
                        let failureCode = response.body.safeFailureCode ?? .transportFailed
                        return await failBeforeStart(
                            failureCode: failureCode,
                            sessionID: sessionID,
                            profileID: profileID,
                            model: model
                        )
                    }

                    startAccepted = true
                    let selected = await model.selectHelperVideoVisualTransport(
                        descriptor: response.body.streamDescriptor,
                        health: HelperVideoStreamHealth(state: .starting)
                    )
                    guard selected else {
                        await renderer.flush()
                        return HelperVideoStreamSessionOutcome(
                            startAccepted: true,
                            selectedVisualTransport: false,
                            receivedAccessUnitCount: receivedAccessUnitCount,
                            displayableFrameCount: 0,
                            droppedAccessUnitCount: droppedAccessUnitCount,
                            fallbackFailureCode: .fallbackToVNC,
                            finalHealth: await helperVideoStreamHealth(model: model)
                        )
                    }
                    selectedVisualTransport = true
                    supportsKeyframeRequest = response.body.streamDescriptor.supportsKeyframeRequest
                    await renderer.flush()
                case .accessUnit(let accessUnit):
                    receivedAccessUnitCount += 1
                    guard selectedVisualTransport else {
                        continue
                    }
                    if recoveryPolicy.isRecovering {
                        recoveryPolicy.recordReceivedAccessUnitWhileRecovering()
                    }
                    do {
                        switch try await renderAccessUnit(
                            accessUnit,
                            backpressureGate: &renderBackpressureGate
                        ) {
                        case .droppedForBackpressure:
                            droppedAccessUnitCount += 1
                            if didPublishHealthy && !didPublishBackpressureHealth {
                                didPublishBackpressureHealth = true
                                await model.updateHelperVideoStreamHealth(
                                    healthyHealth(droppedAccessUnitCount: droppedAccessUnitCount),
                                    sessionID: sessionID,
                                    profileID: profileID
                                )
                            }
                            if recoveryPolicy.isBudgetExhausted {
                                return await decoderRejectedFallback(
                                    startAccepted: startAccepted,
                                    selectedVisualTransport: selectedVisualTransport,
                                    receivedAccessUnitCount: receivedAccessUnitCount,
                                    displayableFrameCount: displayableFrameCount,
                                    droppedAccessUnitCount: droppedAccessUnitCount,
                                    sessionID: sessionID,
                                    profileID: profileID,
                                    model: model
                                )
                            }
                        case .displayable:
                            recoveryPolicy.noteDisplayableFrame()
                            displayableFrameCount += 1
                            if !didPublishHealthy {
                                didPublishHealthy = true
                                await model.updateHelperVideoStreamHealth(
                                    healthyHealth(droppedAccessUnitCount: droppedAccessUnitCount),
                                    sessionID: sessionID,
                                    profileID: profileID
                                )
                                await markProfileAvailable(
                                    sessionID: sessionID,
                                    profileID: profileID,
                                    model: model
                                )
                            }
                        case .notDisplayable:
                            if recoveryPolicy.isBudgetExhausted {
                                return await decoderRejectedFallback(
                                    startAccepted: startAccepted,
                                    selectedVisualTransport: selectedVisualTransport,
                                    receivedAccessUnitCount: receivedAccessUnitCount,
                                    displayableFrameCount: displayableFrameCount,
                                    droppedAccessUnitCount: droppedAccessUnitCount,
                                    sessionID: sessionID,
                                    profileID: profileID,
                                    model: model
                                )
                            }
                        }
                    } catch {
                        let canRecover = supportsKeyframeRequest && requestKeyframe != nil
                        if canRecover {
                            switch recoveryPolicy.handleDecoderRejection(
                                supportsKeyframeRequest: true
                            ) {
                            case .requestKeyframe:
                                requestKeyframe?(.decoderRecovery)
                                continue
                            case .swallow:
                                if !recoveryPolicy.isBudgetExhausted {
                                    continue
                                }
                            case .fallback:
                                break
                            }
                        }
                        return await decoderRejectedFallback(
                            startAccepted: startAccepted,
                            selectedVisualTransport: selectedVisualTransport,
                            receivedAccessUnitCount: receivedAccessUnitCount,
                            displayableFrameCount: displayableFrameCount,
                            droppedAccessUnitCount: droppedAccessUnitCount,
                            sessionID: sessionID,
                            profileID: profileID,
                            model: model
                        )
                    }
                case .stall(let stall):
                    // StreamStalled is terminal for helper-video schema v1:
                    // even if the reason is encoder/backpressure-related, the
                    // current visual stream is no longer producing displayable
                    // frames. Future recoverable stalls should use a distinct
                    // event/retry contract before bypassing VNC fallback.
                    await renderer.flush()
                    let health = fallbackHealth(for: .streamStalled, reportedHealth: stall.body.health)
                    await model.updateHelperVideoStreamHealth(
                        health,
                        sessionID: sessionID,
                        profileID: profileID
                    )
                    await markProfileFailure(
                        .streamStalled,
                        sessionID: sessionID,
                        profileID: profileID,
                        model: model
                    )
                    return HelperVideoStreamSessionOutcome(
                        startAccepted: startAccepted,
                        selectedVisualTransport: selectedVisualTransport,
                        receivedAccessUnitCount: receivedAccessUnitCount,
                        displayableFrameCount: displayableFrameCount,
                        droppedAccessUnitCount: droppedAccessUnitCount,
                        fallbackFailureCode: .streamStalled,
                        finalHealth: await helperVideoStreamHealth(model: model),
                        fallbackStallReason: stall.body.reason
                    )
                }
            }
        } catch {
            guard await isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return await ignoreStaleResult(
                    startAccepted: startAccepted,
                    receivedAccessUnitCount: receivedAccessUnitCount,
                    fallbackFailureCode: helperVideoFailureCode(
                        for: error,
                        startAccepted: startAccepted
                    ),
                    model: model
                )
            }
            let failureCode = helperVideoFailureCode(for: error, startAccepted: startAccepted)
            let health = fallbackHealth(for: failureCode)
            await renderer.flush()
            await model.updateHelperVideoStreamHealth(
                health,
                sessionID: sessionID,
                profileID: profileID
            )
            await markProfileFailure(
                failureCode,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
            return HelperVideoStreamSessionOutcome(
                startAccepted: startAccepted,
                selectedVisualTransport: selectedVisualTransport,
                receivedAccessUnitCount: receivedAccessUnitCount,
                displayableFrameCount: displayableFrameCount,
                droppedAccessUnitCount: droppedAccessUnitCount,
                fallbackFailureCode: failureCode,
                finalHealth: await helperVideoStreamHealth(model: model)
            )
        }

        if displayableFrameCount > 0 {
            return HelperVideoStreamSessionOutcome(
                startAccepted: startAccepted,
                selectedVisualTransport: selectedVisualTransport,
                receivedAccessUnitCount: receivedAccessUnitCount,
                displayableFrameCount: displayableFrameCount,
                droppedAccessUnitCount: droppedAccessUnitCount,
                finalHealth: await helperVideoStreamHealth(model: model)
            )
        }

        return await failBeforeStart(
            failureCode: startAccepted ? .streamStalled : .transportFailed,
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )
    }

    func handleStartResult(
        _ result: HelperVideoStreamNetworkStartResult,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async -> HelperVideoStreamSessionOutcome {
        guard result.startResponse.body.result == .accepted else {
            let failureCode = result.startResponse.body.safeFailureCode ?? .transportFailed
            guard await isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return await ignoreStaleResult(
                    startAccepted: false,
                    receivedAccessUnitCount: result.accessUnits.count,
                    fallbackFailureCode: failureCode,
                    model: model
                )
            }
            return await failBeforeStart(
                failureCode: failureCode,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        guard await isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
            return await ignoreStaleResult(
                startAccepted: true,
                receivedAccessUnitCount: result.accessUnits.count,
                fallbackFailureCode: .fallbackToVNC,
                model: model
            )
        }

        let startingHealth = HelperVideoStreamHealth(state: .starting)
        let selected = await model.selectHelperVideoVisualTransport(
            descriptor: result.startResponse.body.streamDescriptor,
            health: startingHealth
        )
        guard selected else {
            await renderer.flush()
            // Selection can fail because the app/session gate rejected the visual switch.
            // Preserve profile failure state so policy rejection stays distinct from
            // helper transport, stall, or decoder failure.
            return HelperVideoStreamSessionOutcome(
                startAccepted: true,
                selectedVisualTransport: false,
                receivedAccessUnitCount: result.accessUnits.count,
                displayableFrameCount: 0,
                fallbackFailureCode: .fallbackToVNC,
                finalHealth: await helperVideoStreamHealth(model: model)
            )
        }

        await renderer.flush()
        var displayableFrameCount = 0
        var droppedAccessUnitCount = 0
        var renderBackpressureGate = HelperVideoRenderBackpressureGate()

        for accessUnit in result.accessUnits {
            do {
                switch try await renderAccessUnit(
                    accessUnit,
                    backpressureGate: &renderBackpressureGate
                ) {
                case .droppedForBackpressure:
                    droppedAccessUnitCount += 1
                case .displayable:
                    displayableFrameCount += 1
                case .notDisplayable:
                    break
                }
            } catch {
                return await decoderRejectedFallback(
                    startAccepted: true,
                    selectedVisualTransport: true,
                    receivedAccessUnitCount: result.accessUnits.count,
                    displayableFrameCount: displayableFrameCount,
                    droppedAccessUnitCount: droppedAccessUnitCount,
                    sessionID: sessionID,
                    profileID: profileID,
                    model: model
                )
            }
        }

        if let stall = result.stall {
            await renderer.flush()
            let health = fallbackHealth(for: .streamStalled, reportedHealth: stall.body.health)
            await model.updateHelperVideoStreamHealth(
                health,
                sessionID: sessionID,
                profileID: profileID
            )
            await markProfileFailure(
                .streamStalled,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
            return HelperVideoStreamSessionOutcome(
                startAccepted: true,
                selectedVisualTransport: true,
                receivedAccessUnitCount: result.accessUnits.count,
                displayableFrameCount: displayableFrameCount,
                droppedAccessUnitCount: droppedAccessUnitCount,
                fallbackFailureCode: .streamStalled,
                finalHealth: await helperVideoStreamHealth(model: model),
                fallbackStallReason: stall.body.reason
            )
        }

        guard displayableFrameCount > 0 else {
            await renderer.flush()
            let health = fallbackHealth(for: .streamStalled)
            await model.updateHelperVideoStreamHealth(
                health,
                sessionID: sessionID,
                profileID: profileID
            )
            await markProfileFailure(
                .streamStalled,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
            return HelperVideoStreamSessionOutcome(
                startAccepted: true,
                selectedVisualTransport: true,
                receivedAccessUnitCount: result.accessUnits.count,
                displayableFrameCount: 0,
                droppedAccessUnitCount: droppedAccessUnitCount,
                fallbackFailureCode: .streamStalled,
                finalHealth: await helperVideoStreamHealth(model: model)
            )
        }

        await model.updateHelperVideoStreamHealth(
            healthyHealth(droppedAccessUnitCount: droppedAccessUnitCount),
            sessionID: sessionID,
            profileID: profileID
        )
        await markProfileAvailable(
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )

        return HelperVideoStreamSessionOutcome(
            startAccepted: true,
            selectedVisualTransport: true,
            receivedAccessUnitCount: result.accessUnits.count,
            displayableFrameCount: displayableFrameCount,
            droppedAccessUnitCount: droppedAccessUnitCount,
            finalHealth: await helperVideoStreamHealth(model: model)
        )
    }

    private func renderAccessUnit(
        _ accessUnit: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>,
        backpressureGate: inout HelperVideoRenderBackpressureGate
    ) async throws -> HelperVideoAccessUnitRenderResult {
        switch backpressureGate.decision(for: accessUnit.envelope.body.kind) {
        case .dropDeltaWithoutQuery:
            return .droppedForBackpressure
        case .renderWithoutQuery:
            return try await renderer.enqueueDisplayableAccessUnit(accessUnit)
                ? .displayable
                : .notDisplayable
        case .queryRendererBackpressure:
            let shouldDrop = await renderer.shouldDropAccessUnitForBackpressure(accessUnit)
            backpressureGate.recordRendererBackpressureResult(
                for: accessUnit.envelope.body.kind,
                shouldDrop: shouldDrop
            )
            guard !shouldDrop else {
                return .droppedForBackpressure
            }
            return try await renderer.enqueueDisplayableAccessUnit(accessUnit)
                ? .displayable
                : .notDisplayable
        }
    }

    private func decoderRejectedFallback(
        startAccepted: Bool,
        selectedVisualTransport: Bool,
        receivedAccessUnitCount: Int,
        displayableFrameCount: Int,
        droppedAccessUnitCount: Int,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async -> HelperVideoStreamSessionOutcome {
        await renderer.flush()
        let health = fallbackHealth(for: .decoderRejected)
        await model.updateHelperVideoStreamHealth(
            health,
            sessionID: sessionID,
            profileID: profileID
        )
        await markProfileFailure(
            .decoderRejected,
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )
        return HelperVideoStreamSessionOutcome(
            startAccepted: startAccepted,
            selectedVisualTransport: selectedVisualTransport,
            receivedAccessUnitCount: receivedAccessUnitCount,
            displayableFrameCount: displayableFrameCount,
            droppedAccessUnitCount: droppedAccessUnitCount,
            fallbackFailureCode: .decoderRejected,
            finalHealth: await helperVideoStreamHealth(model: model)
        )
    }

    private func ignoreStaleResult(
        startAccepted: Bool,
        receivedAccessUnitCount: Int,
        fallbackFailureCode: HelperVideoFailureCode?,
        model: NaruRemoteAppModel
    ) async -> HelperVideoStreamSessionOutcome {
        await renderer.flush()
        return HelperVideoStreamSessionOutcome(
            startAccepted: startAccepted,
            selectedVisualTransport: false,
            receivedAccessUnitCount: receivedAccessUnitCount,
            displayableFrameCount: 0,
            fallbackFailureCode: fallbackFailureCode,
            finalHealth: await helperVideoStreamHealth(model: model)
        )
    }

    private func failBeforeStart(
        failureCode: HelperVideoFailureCode,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async -> HelperVideoStreamSessionOutcome {
        await renderer.flush()
        let health = fallbackHealth(for: failureCode)
        await model.updateHelperVideoStreamHealth(
            health,
            sessionID: sessionID,
            profileID: profileID
        )
        await markProfileFailure(
            failureCode,
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )
        return HelperVideoStreamSessionOutcome(
            startAccepted: false,
            selectedVisualTransport: false,
            receivedAccessUnitCount: 0,
            displayableFrameCount: 0,
            fallbackFailureCode: failureCode,
            finalHealth: await helperVideoStreamHealth(model: model)
        )
    }

    private func markProfileAvailable(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async {
        var state = await model.snapshot.helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.isEnabled = true
        state.availability = .available
        state.lastFailureCode = nil
        state.lastCheckedBucket = .recent
        await model.setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func markProfileFailure(
        _ failureCode: HelperVideoFailureCode,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async {
        var state = await model.snapshot.helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.availability = availability(for: failureCode)
        state.lastFailureCode = failureCode
        state.lastCheckedBucket = .recent
        await model.setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func isCurrentSession(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) async -> Bool {
        let snapshot = await model.snapshot
        return snapshot.session?.id == sessionID
            && snapshot.session?.profileID == profileID
            && snapshot.selectedProfileID == profileID
    }

    private func helperVideoStreamHealth(model: NaruRemoteAppModel) async -> HelperVideoStreamHealth {
        await model.snapshot.helperVideoStreamHealth
    }

    private func healthyHealth(droppedAccessUnitCount: Int) -> HelperVideoStreamHealth {
        HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: droppedAccessUnitCount > 0 ? .usable : .smooth,
            decodePressure: droppedAccessUnitCount > 0 ? .medium : .low
        )
    }

    private func availability(for failureCode: HelperVideoFailureCode) -> HelperVideoAvailability {
        switch failureCode {
        case .notConfigured:
            return .notConfigured
        case .disabled:
            return .disabled
        case .permissionMissing:
            return .permissionMissing
        case .codecUnsupported:
            return .codecUnsupported
        case .revoked:
            return .revoked
        case .privateNetworkRequired:
            return .privateNetworkRequired
        case .transportFailed, .transportProtectionRequired:
            return .unreachable
        case .authFailed, .streamStalled, .decoderRejected, .fallbackToVNC:
            return .failed
        }
    }

    private func fallbackHealth(
        for failureCode: HelperVideoFailureCode,
        reportedHealth: HelperVideoStreamHealth? = nil
    ) -> HelperVideoStreamHealth {
        if let reportedHealth,
           reportedHealth.shouldUseVNCVisualFallback {
            return HelperVideoStreamHealth(
                state: .fallbackToVNC,
                startupBand: reportedHealth.startupBand,
                sustainedUpdateBand: reportedHealth.sustainedUpdateBand,
                decodePressure: reportedHealth.decodePressure,
                fallbackCountBucket: reportedHealth.fallbackCountBucket == .none
                    ? .one
                    : reportedHealth.fallbackCountBucket
            )
        }

        switch failureCode {
        case .decoderRejected:
            return HelperVideoStreamHealth(
                state: .fallbackToVNC,
                startupBand: .failed,
                sustainedUpdateBand: .stalled,
                decodePressure: .high,
                fallbackCountBucket: .one
            )
        case .streamStalled:
            return HelperVideoStreamHealth(
                state: .fallbackToVNC,
                startupBand: .failed,
                sustainedUpdateBand: .stalled,
                decodePressure: .notMeasured,
                fallbackCountBucket: .one
            )
        case .permissionMissing, .codecUnsupported, .privateNetworkRequired, .notConfigured,
             .disabled, .revoked, .authFailed, .transportFailed, .transportProtectionRequired,
             .fallbackToVNC:
            return HelperVideoStreamHealth(
                state: .fallbackToVNC,
                startupBand: .failed,
                sustainedUpdateBand: .stalled,
                decodePressure: .notMeasured,
                fallbackCountBucket: .one
            )
        }
    }

    private func helperVideoFailureCode(
        for error: any Error,
        startAccepted: Bool
    ) -> HelperVideoFailureCode {
        #if canImport(Network)
        if let clientError = error as? HelperVideoStreamNetworkClientError,
           clientError == .transportProtectionRequired {
            return .transportProtectionRequired
        }
        #endif
        return startAccepted ? .streamStalled : .transportFailed
    }
}
