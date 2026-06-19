import Foundation
import NaruRemoteCore

public struct NaruHelperVideoAccessUnit: Equatable, Sendable {
    public var sequence: Int
    public var kind: HelperVideoAccessUnitKind
    public var binaryPayload: Data

    public init(
        sequence: Int,
        kind: HelperVideoAccessUnitKind,
        binaryPayload: Data
    ) {
        self.sequence = max(sequence, 0)
        self.kind = kind
        self.binaryPayload = binaryPayload
    }

    func envelope(
        requestID: UUID,
        profileFingerprint: String?
    ) -> HelperVideoWireEnvelope<HelperVideoAccessUnitBody> {
        HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: .videoAccessUnit,
            profileFingerprint: profileFingerprint,
            authProof: nil,
            body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
        )
    }
}

public protocol NaruHelperVideoAccessUnitSource: Sendable {
    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit]

    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
}

public extension NaruHelperVideoAccessUnitSource {
    func accessUnitStream(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error> {
        let accessUnits = try accessUnits(for: request)
        return AsyncThrowingStream { continuation in
            for accessUnit in accessUnits {
                continuation.yield(accessUnit)
            }
            continuation.finish()
        }
    }
}

public struct NaruHelperVideoStaticAccessUnitSource: NaruHelperVideoAccessUnitSource {
    private let accessUnits: [NaruHelperVideoAccessUnit]

    public init(accessUnits: [NaruHelperVideoAccessUnit]) {
        self.accessUnits = accessUnits
    }

    public func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        accessUnits
    }
}

public struct NaruHelperVideoOpenedFrameStream: Sendable {
    public let responseFrame: Data
    public let isAccepted: Bool

    private let request: HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>
    private let emptyStreamHealth: HelperVideoStreamHealth
    private let accessUnitStreamFactory:
        @Sendable () throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>

    init(
        responseFrame: Data,
        isAccepted: Bool,
        request: HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>,
        emptyStreamHealth: HelperVideoStreamHealth,
        accessUnitStreamFactory:
            @escaping @Sendable () throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
    ) {
        self.responseFrame = responseFrame
        self.isAccepted = isAccepted
        self.request = request
        self.emptyStreamHealth = emptyStreamHealth
        self.accessUnitStreamFactory = accessUnitStreamFactory
    }

    public func makeAccessUnitStream()
        throws -> AsyncThrowingStream<NaruHelperVideoAccessUnit, any Error>
    {
        try accessUnitStreamFactory()
    }

    public func frame(for accessUnit: NaruHelperVideoAccessUnit) throws -> Data {
        try HelperVideoWireCodec.frameAccessUnit(
            accessUnit.envelope(
                requestID: request.requestID,
                profileFingerprint: request.profileFingerprint
            ),
            binaryPayload: accessUnit.binaryPayload
        )
    }

    public func stalledFrameForEmptyStream(
        reason: HelperVideoStreamStallReason = .noAccessUnit
    ) throws -> Data {
        let envelope = HelperVideoWireEnvelope(
            requestID: request.requestID,
            messageType: .streamStalled,
            profileFingerprint: request.profileFingerprint,
            authProof: nil,
            body: HelperVideoStreamStallBody(
                reason: reason,
                health: emptyStreamHealth
            )
        )
        return try HelperVideoWireCodec.frame(envelope)
    }

    func stalledFrameForSourceFailure(
        _ error: any Error,
        emittedAccessUnit: Bool
    ) throws -> Data? {
        guard let reason = Self.stallReasonForSourceFailure(
            error,
            emittedAccessUnit: emittedAccessUnit
        ) else {
            return nil
        }
        return try stalledFrameForEmptyStream(reason: reason)
    }

    private static func stallReasonForSourceFailure(
        _ error: any Error,
        emittedAccessUnit: Bool
    ) -> HelperVideoStreamStallReason? {
        guard !emittedAccessUnit else {
            return nil
        }
        guard let screenCaptureError =
            error as? NaruHelperVideoScreenCaptureKitAccessUnitSourceError
        else {
            return nil
        }

        switch screenCaptureError {
        case .captureSourceUnavailable, .unsupportedPlatform:
            return .screenCaptureSourceUnavailable
        case .captureTimedOut, .noCapturedFrames:
            return .screenCaptureTimedOut
        case .captureNoOutputCallbacks:
            return .screenCaptureNoOutputCallbacks
        case .captureNonScreenOutputCallbacks:
            return .screenCaptureNonScreenCallbacks
        case .captureNonDisplayableScreenFrames:
            return .screenCaptureNonDisplayableFrames
        case .capturedFrameMissingImageBuffer:
            return .screenCaptureMissingImageBuffer
        case .captureInsufficientDisplayableFrames:
            return .screenCaptureInsufficientDisplayableFrames
        case .captureFailed:
            return .screenCaptureFailed
        case .screenRecordingPermissionMissing:
            return .screenCaptureSourceUnavailable
        }
    }
}

public struct NaruHelperVideoStreamFramePipeline: Sendable {
    private let requestHandler: NaruHelperVideoTransportRequestHandler
    private let accessUnitSource: any NaruHelperVideoAccessUnitSource
    private let emptyStreamHealth: HelperVideoStreamHealth

    public init(
        requestHandler: NaruHelperVideoTransportRequestHandler,
        accessUnitSource: any NaruHelperVideoAccessUnitSource,
        emptyStreamHealth: HelperVideoStreamHealth = HelperVideoStreamHealth(
            state: .stalled,
            startupBand: .failed,
            sustainedUpdateBand: .stalled,
            decodePressure: .notMeasured,
            fallbackCountBucket: .one
        )
    ) {
        self.requestHandler = requestHandler
        self.accessUnitSource = accessUnitSource
        self.emptyStreamHealth = emptyStreamHealth
    }

    public func frames(forStartStreamFrame frame: Data) throws -> [Data] {
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>.self,
            from: frame
        )
        let request = decoded.envelope
        let response = requestHandler.handleStartStreamRequest(request)
        var frames = [try HelperVideoWireCodec.frame(response)]

        guard response.body.result == .accepted else {
            return frames
        }

        let accessUnits = try accessUnitSource.accessUnits(for: request.body)
        guard !accessUnits.isEmpty else {
            frames.append(try stalledFrame(for: request))
            return frames
        }

        // Emit the stream batch all-or-nothing so callers never consume a partial
        // helper stream after a malformed or oversized access unit.
        frames.append(contentsOf: try accessUnits.map { accessUnit in
            try HelperVideoWireCodec.frameAccessUnit(
                accessUnit.envelope(
                    requestID: request.requestID,
                    profileFingerprint: request.profileFingerprint
                ),
                binaryPayload: accessUnit.binaryPayload
            )
        })
        return frames
    }

    public func frameStream(
        forStartStreamFrame frame: Data
    ) throws -> AsyncThrowingStream<Data, any Error> {
        let openedStream = try openFrameStream(forStartStreamFrame: frame)
        guard openedStream.isAccepted else {
            return AsyncThrowingStream { continuation in
                continuation.yield(openedStream.responseFrame)
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(openedStream.responseFrame)

            let producer = Task {
                var emittedAccessUnit = false
                do {
                    let accessUnitStream = try openedStream.makeAccessUnitStream()
                    for try await accessUnit in accessUnitStream {
                        try Task.checkCancellation()
                        emittedAccessUnit = true
                        continuation.yield(try openedStream.frame(for: accessUnit))
                    }

                    if !emittedAccessUnit {
                        continuation.yield(try openedStream.stalledFrameForEmptyStream())
                    }
                    continuation.finish()
                } catch {
                    if let stallFrame = try openedStream.stalledFrameForSourceFailure(
                        error,
                        emittedAccessUnit: emittedAccessUnit
                    ) {
                        continuation.yield(stallFrame)
                        continuation.finish()
                        return
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    public func openFrameStream(
        forStartStreamFrame frame: Data
    ) throws -> NaruHelperVideoOpenedFrameStream {
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>.self,
            from: frame
        )
        let request = decoded.envelope
        let response = requestHandler.handleStartStreamRequest(request)
        let responseFrame = try HelperVideoWireCodec.frame(response)

        return NaruHelperVideoOpenedFrameStream(
            responseFrame: responseFrame,
            isAccepted: response.body.result == .accepted,
            request: request,
            emptyStreamHealth: emptyStreamHealth,
            accessUnitStreamFactory: { [accessUnitSource] in
                try accessUnitSource.accessUnitStream(for: request.body)
            }
        )
    }

    private func stalledFrame(
        for request: HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>
    ) throws -> Data {
        let envelope = HelperVideoWireEnvelope(
            requestID: request.requestID,
            messageType: .streamStalled,
            profileFingerprint: request.profileFingerprint,
            authProof: nil,
            body: HelperVideoStreamStallBody(
                reason: .noAccessUnit,
                health: emptyStreamHealth
            )
        )
        return try HelperVideoWireCodec.frame(envelope)
    }

}
