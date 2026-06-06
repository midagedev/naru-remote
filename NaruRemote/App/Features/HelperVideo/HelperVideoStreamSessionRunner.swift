import Foundation
import NaruRemoteCore

@MainActor
public protocol HelperVideoAccessUnitRendering: AnyObject {
    @discardableResult
    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> Bool

    func flush()
}

private final class HelperVideoMainActorRendererBox: @unchecked Sendable {
    private let renderer: any HelperVideoAccessUnitRendering

    init(_ renderer: any HelperVideoAccessUnitRendering) {
        self.renderer = renderer
    }

    @MainActor
    @discardableResult
    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) throws -> Bool {
        try renderer.enqueueDisplayableAccessUnit(decoded)
    }

    @MainActor
    func flush() {
        renderer.flush()
    }
}

public struct HelperVideoStreamSessionOutcome: Equatable, Sendable {
    public var startAccepted: Bool
    public var selectedVisualTransport: Bool
    public var receivedAccessUnitCount: Int
    public var displayableFrameCount: Int
    public var fallbackFailureCode: HelperVideoFailureCode?
    public var finalHealth: HelperVideoStreamHealth

    public init(
        startAccepted: Bool,
        selectedVisualTransport: Bool,
        receivedAccessUnitCount: Int,
        displayableFrameCount: Int,
        fallbackFailureCode: HelperVideoFailureCode? = nil,
        finalHealth: HelperVideoStreamHealth
    ) {
        self.startAccepted = startAccepted
        self.selectedVisualTransport = selectedVisualTransport
        self.receivedAccessUnitCount = max(receivedAccessUnitCount, 0)
        self.displayableFrameCount = max(displayableFrameCount, 0)
        self.fallbackFailureCode = fallbackFailureCode
        self.finalHealth = finalHealth
    }
}

public final class HelperVideoStreamSessionRunner: @unchecked Sendable {
    public typealias StartStream = @Sendable (
        HelperVideoStartStreamRequestBody,
        Int
    ) async throws -> HelperVideoStreamNetworkStartResult

    private let startStream: StartStream
    private let renderer: HelperVideoMainActorRendererBox
    private let maxServerFrames: Int

    public init(
        startStream: @escaping StartStream,
        renderer: any HelperVideoAccessUnitRendering,
        maxServerFrames: Int = 16
    ) {
        self.startStream = startStream
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
            startStream: { requestBody, maxServerFrames in
                try await networkClient.startStream(
                    requestBody,
                    maxServerFrames: maxServerFrames
                )
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
        let result: HelperVideoStreamNetworkStartResult
        do {
            result = try await startStream(requestBody, maxServerFrames)
        } catch {
            guard await isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return await ignoreStaleResult(
                    startAccepted: false,
                    receivedAccessUnitCount: 0,
                    fallbackFailureCode: .transportFailed,
                    model: model
                )
            }
            return await failBeforeStart(
                failureCode: .transportFailed,
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

        for accessUnit in result.accessUnits {
            do {
                if try await renderer.enqueueDisplayableAccessUnit(accessUnit) {
                    displayableFrameCount += 1
                }
            } catch {
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
                    startAccepted: true,
                    selectedVisualTransport: true,
                    receivedAccessUnitCount: result.accessUnits.count,
                    displayableFrameCount: displayableFrameCount,
                    fallbackFailureCode: .decoderRejected,
                    finalHealth: await helperVideoStreamHealth(model: model)
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
                fallbackFailureCode: .streamStalled,
                finalHealth: await helperVideoStreamHealth(model: model)
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
                fallbackFailureCode: .streamStalled,
                finalHealth: await helperVideoStreamHealth(model: model)
            )
        }

        let healthy = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low
        )
        await model.updateHelperVideoStreamHealth(
            healthy,
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
        case .transportFailed:
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
             .disabled, .revoked, .authFailed, .transportFailed, .fallbackToVNC:
            return HelperVideoStreamHealth(
                state: .fallbackToVNC,
                startupBand: .failed,
                sustainedUpdateBand: .stalled,
                decodePressure: .notMeasured,
                fallbackCountBucket: .one
            )
        }
    }
}
