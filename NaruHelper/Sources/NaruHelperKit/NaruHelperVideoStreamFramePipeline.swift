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
        let decoded = try HelperVideoWireCodec.decodeFrame(
            HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>.self,
            from: frame
        )
        let request = decoded.envelope
        let response = requestHandler.handleStartStreamRequest(request)
        let responseFrame = try HelperVideoWireCodec.frame(response)

        guard response.body.result == .accepted else {
            return AsyncThrowingStream { continuation in
                continuation.yield(responseFrame)
                continuation.finish()
            }
        }

        let accessUnitStream = try accessUnitSource.accessUnitStream(for: request.body)
        let emptyStreamHealth = emptyStreamHealth
        return AsyncThrowingStream { continuation in
            continuation.yield(responseFrame)

            let producer = Task {
                var emittedAccessUnit = false
                do {
                    for try await accessUnit in accessUnitStream {
                        try Task.checkCancellation()
                        let accessUnitFrame = try HelperVideoWireCodec.frameAccessUnit(
                            accessUnit.envelope(
                                requestID: request.requestID,
                                profileFingerprint: request.profileFingerprint
                            ),
                            binaryPayload: accessUnit.binaryPayload
                        )
                        emittedAccessUnit = true
                        continuation.yield(accessUnitFrame)
                    }

                    if !emittedAccessUnit {
                        continuation.yield(
                            try Self.stalledFrame(
                                for: request,
                                health: emptyStreamHealth
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
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

    private static func stalledFrame(
        for request: HelperVideoWireEnvelope<HelperVideoStartStreamRequestBody>,
        health: HelperVideoStreamHealth
    ) throws -> Data {
        let envelope = HelperVideoWireEnvelope(
            requestID: request.requestID,
            messageType: .streamStalled,
            profileFingerprint: request.profileFingerprint,
            authProof: nil,
            body: HelperVideoStreamStallBody(
                reason: .noAccessUnit,
                health: health
            )
        )
        return try HelperVideoWireCodec.frame(envelope)
    }
}
