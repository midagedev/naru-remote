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

@MainActor
public final class HelperVideoStreamSessionRunner {
    public typealias StartStream = (
        HelperVideoStartStreamRequestBody,
        Int
    ) async throws -> HelperVideoStreamNetworkStartResult

    private let startStream: StartStream
    private let renderer: any HelperVideoAccessUnitRendering
    private let maxServerFrames: Int

    public init(
        startStream: @escaping StartStream,
        renderer: any HelperVideoAccessUnitRendering,
        maxServerFrames: Int = 16
    ) {
        self.startStream = startStream
        self.renderer = renderer
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
            guard isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return ignoreStaleResult(
                    startAccepted: false,
                    receivedAccessUnitCount: 0,
                    fallbackFailureCode: .transportFailed,
                    model: model
                )
            }
            return failBeforeStart(
                failureCode: .transportFailed,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        return handleStartResult(
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
    ) -> HelperVideoStreamSessionOutcome {
        guard result.startResponse.body.result == .accepted else {
            let failureCode = result.startResponse.body.safeFailureCode ?? .transportFailed
            guard isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
                return ignoreStaleResult(
                    startAccepted: false,
                    receivedAccessUnitCount: result.accessUnits.count,
                    fallbackFailureCode: failureCode,
                    model: model
                )
            }
            return failBeforeStart(
                failureCode: failureCode,
                sessionID: sessionID,
                profileID: profileID,
                model: model
            )
        }

        guard isCurrentSession(sessionID: sessionID, profileID: profileID, model: model) else {
            return ignoreStaleResult(
                startAccepted: true,
                receivedAccessUnitCount: result.accessUnits.count,
                fallbackFailureCode: .fallbackToVNC,
                model: model
            )
        }

        let startingHealth = HelperVideoStreamHealth(state: .starting)
        let selected = model.selectHelperVideoVisualTransport(
            descriptor: result.startResponse.body.streamDescriptor,
            health: startingHealth
        )
        guard selected else {
            renderer.flush()
            // Selection can fail because the app/session gate rejected the visual switch.
            // Preserve profile failure state so policy rejection stays distinct from
            // helper transport, stall, or decoder failure.
            return HelperVideoStreamSessionOutcome(
                startAccepted: true,
                selectedVisualTransport: false,
                receivedAccessUnitCount: result.accessUnits.count,
                displayableFrameCount: 0,
                fallbackFailureCode: .fallbackToVNC,
                finalHealth: model.snapshot.helperVideoStreamHealth
            )
        }

        renderer.flush()
        var displayableFrameCount = 0

        for accessUnit in result.accessUnits {
            do {
                if try renderer.enqueueDisplayableAccessUnit(accessUnit) {
                    displayableFrameCount += 1
                }
            } catch {
                renderer.flush()
                let health = fallbackHealth(for: .decoderRejected)
                model.updateHelperVideoStreamHealth(
                    health,
                    sessionID: sessionID,
                    profileID: profileID
                )
                markProfileFailure(
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
                    finalHealth: model.snapshot.helperVideoStreamHealth
                )
            }
        }

        if let stall = result.stall {
            renderer.flush()
            let health = fallbackHealth(for: .streamStalled, reportedHealth: stall.body.health)
            model.updateHelperVideoStreamHealth(
                health,
                sessionID: sessionID,
                profileID: profileID
            )
            markProfileFailure(
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
                finalHealth: model.snapshot.helperVideoStreamHealth
            )
        }

        guard displayableFrameCount > 0 else {
            renderer.flush()
            let health = fallbackHealth(for: .streamStalled)
            model.updateHelperVideoStreamHealth(
                health,
                sessionID: sessionID,
                profileID: profileID
            )
            markProfileFailure(
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
                finalHealth: model.snapshot.helperVideoStreamHealth
            )
        }

        let healthy = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low
        )
        model.updateHelperVideoStreamHealth(
            healthy,
            sessionID: sessionID,
            profileID: profileID
        )
        markProfileAvailable(
            sessionID: sessionID,
            profileID: profileID,
            model: model
        )

        return HelperVideoStreamSessionOutcome(
            startAccepted: true,
            selectedVisualTransport: true,
            receivedAccessUnitCount: result.accessUnits.count,
            displayableFrameCount: displayableFrameCount,
            finalHealth: model.snapshot.helperVideoStreamHealth
        )
    }

    private func ignoreStaleResult(
        startAccepted: Bool,
        receivedAccessUnitCount: Int,
        fallbackFailureCode: HelperVideoFailureCode?,
        model: NaruRemoteAppModel
    ) -> HelperVideoStreamSessionOutcome {
        renderer.flush()
        return HelperVideoStreamSessionOutcome(
            startAccepted: startAccepted,
            selectedVisualTransport: false,
            receivedAccessUnitCount: receivedAccessUnitCount,
            displayableFrameCount: 0,
            fallbackFailureCode: fallbackFailureCode,
            finalHealth: model.snapshot.helperVideoStreamHealth
        )
    }

    private func failBeforeStart(
        failureCode: HelperVideoFailureCode,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) -> HelperVideoStreamSessionOutcome {
        renderer.flush()
        let health = fallbackHealth(for: failureCode)
        model.updateHelperVideoStreamHealth(
            health,
            sessionID: sessionID,
            profileID: profileID
        )
        markProfileFailure(
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
            finalHealth: model.snapshot.helperVideoStreamHealth
        )
    }

    private func markProfileAvailable(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) {
        var state = model.snapshot.helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.isEnabled = true
        state.availability = .available
        state.lastFailureCode = nil
        state.lastCheckedBucket = .recent
        model.setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func markProfileFailure(
        _ failureCode: HelperVideoFailureCode,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) {
        var state = model.snapshot.helperVideoProfileState[profileID] ?? HelperVideoProfileState()
        state.availability = availability(for: failureCode)
        state.lastFailureCode = failureCode
        state.lastCheckedBucket = .recent
        model.setHelperVideoProfileState(state, for: profileID, sessionID: sessionID)
    }

    private func isCurrentSession(
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID,
        model: NaruRemoteAppModel
    ) -> Bool {
        let snapshot = model.snapshot
        return snapshot.session?.id == sessionID
            && snapshot.session?.profileID == profileID
            && snapshot.selectedProfileID == profileID
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
