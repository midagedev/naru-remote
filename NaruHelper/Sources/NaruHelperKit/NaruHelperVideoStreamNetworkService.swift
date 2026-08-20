import Foundation
import NaruRemoteCore

#if canImport(Network)
import Network

public final class NaruHelperVideoStreamNetworkServer: @unchecked Sendable {
    private let pipeline: NaruHelperVideoStreamFramePipeline
    private let queue: DispatchQueue
    private let listener: NWListener

    public init(
        port: UInt16,
        pipeline: NaruHelperVideoStreamFramePipeline,
        transportProtection: HelperVideoTransportProtection,
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-video-stream-server")
    ) throws {
        guard transportProtection.allowsEncodedFramePayloads else {
            throw HelperVideoStreamNetworkServerError.transportProtectionRequired
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw HelperVideoStreamNetworkServerError.invalidPort
        }
        self.pipeline = pipeline
        self.queue = queue
        self.listener = try NWListener(using: .tcp, on: endpointPort)
    }

    public init(
        pipeline: NaruHelperVideoStreamFramePipeline,
        transportProtection: HelperVideoTransportProtection,
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-video-stream-server")
    ) throws {
        guard transportProtection.allowsEncodedFramePayloads else {
            throw HelperVideoStreamNetworkServerError.transportProtectionRequired
        }
        self.pipeline = pipeline
        self.queue = queue
        self.listener = try NWListener(using: .tcp)
    }

    public var port: UInt16? {
        listener.port?.rawValue
    }

    public func start() {
        listener.newConnectionHandler = { [pipeline, queue] connection in
            connection.start(queue: queue)
            Self.receiveStartStreamFrame(on: connection, pipeline: pipeline)
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }

    private static func receiveStartStreamFrame(
        on connection: NWConnection,
        pipeline: NaruHelperVideoStreamFramePipeline
    ) {
        connection.receive(
            minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
            maximumLength: HelperVideoWireCodec.headerByteCount
        ) { header, _, _, error in
            guard error == nil, let header else {
                connection.cancel()
                return
            }

            let length: Int
            do {
                length = try HelperVideoWireCodec.jsonPayloadLength(from: header)
            } catch {
                connection.cancel()
                return
            }

            connection.receive(
                minimumIncompleteLength: length,
                maximumLength: length
            ) { payload, _, _, error in
                guard error == nil, let payload else {
                    connection.cancel()
                    return
                }

                do {
                    let openedStream = try pipeline.openFrameStream(
                        forStartStreamFrame: header + payload
                    )
                    Task.detached(priority: .userInitiated) {
                        await send(openedStream, on: connection)
                    }
                } catch {
                    connection.cancel()
                }
            }
        }
    }

    private static func send(
        _ openedStream: NaruHelperVideoOpenedFrameStream,
        on connection: NWConnection
    ) async {
        var emittedAccessUnit = false
        var inboundControl: Task<Void, Never>?
        do {
            try await sendFrame(openedStream.responseFrame, on: connection)
            guard openedStream.isAccepted else {
                await complete(connection)
                return
            }

            inboundControl = Task {
                await receiveInboundControlFrames(on: connection, stream: openedStream)
            }
            defer {
                inboundControl?.cancel()
            }

            let accessUnitStream = try openedStream.makeAccessUnitStream()
            for try await accessUnit in accessUnitStream {
                try Task.checkCancellation()
                emittedAccessUnit = true
                try await sendFrame(openedStream.frame(for: accessUnit), on: connection)
            }
            if !emittedAccessUnit {
                try await sendFrame(openedStream.stalledFrameForEmptyStream(), on: connection)
            }
            await complete(connection)
        } catch {
            inboundControl?.cancel()
            if let stalledFrame = try? openedStream.stalledFrameForSourceFailure(
                error,
                emittedAccessUnit: emittedAccessUnit
            ) {
                do {
                    try await sendFrame(stalledFrame, on: connection)
                    await complete(connection)
                } catch {
                    connection.cancel()
                }
                return
            }
            connection.cancel()
        }
    }

    private static func receiveInboundControlFrames(
        on connection: NWConnection,
        stream: NaruHelperVideoOpenedFrameStream
    ) async {
        while !Task.isCancelled {
            guard let frame = await receiveJSONFrame(on: connection) else {
                return
            }
            stream.considerInboundControlFrame(frame)
        }
    }

    private static func receiveJSONFrame(on connection: NWConnection) async -> Data? {
        let resume = HelperVideoInboundReceiveResume()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resume.arm(continuation)
                connection.receive(
                    minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
                    maximumLength: HelperVideoWireCodec.headerByteCount
                ) { header, _, _, error in
                    if error != nil {
                        resume.finish(nil)
                        return
                    }
                    guard let header else {
                        resume.finish(nil)
                        return
                    }

                    let length: Int
                    do {
                        length = try HelperVideoWireCodec.jsonPayloadLength(from: header)
                    } catch {
                        resume.finish(nil)
                        return
                    }

                    connection.receive(
                        minimumIncompleteLength: length,
                        maximumLength: length
                    ) { payload, _, _, error in
                        guard error == nil, let payload else {
                            resume.finish(nil)
                            return
                        }
                        resume.finish(header + payload)
                    }
                }
            }
        } onCancel: {
            resume.finish(nil)
        }
    }

    private static func sendFrame(
        _ frame: Data,
        on connection: NWConnection
    ) async throws {
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func complete(_ connection: NWConnection) async {
        await withCheckedContinuation { continuation in
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
                continuation.resume()
            })
        }
    }
}

public enum HelperVideoStreamNetworkServerError: Error, Equatable, Sendable {
    case invalidPort
    case transportProtectionRequired
}

private final class HelperVideoInboundReceiveResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    func arm(_ continuation: CheckedContinuation<Data?, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ frame: Data?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: frame)
    }
}
#endif
