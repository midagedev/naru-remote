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
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-video-stream-server")
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw HelperVideoStreamNetworkServerError.invalidPort
        }
        self.pipeline = pipeline
        self.queue = queue
        self.listener = try NWListener(using: .tcp, on: endpointPort)
    }

    public init(
        pipeline: NaruHelperVideoStreamFramePipeline,
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-video-stream-server")
    ) throws {
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
                    let frames = try pipeline.frames(forStartStreamFrame: header + payload)
                    send(frames[...], on: connection)
                } catch {
                    connection.cancel()
                }
            }
        }
    }

    private static func send(
        _ frames: ArraySlice<Data>,
        on connection: NWConnection
    ) {
        guard let frame = frames.first else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        connection.send(content: frame, completion: .contentProcessed { error in
            guard error == nil else {
                connection.cancel()
                return
            }
            send(frames.dropFirst(), on: connection)
        })
    }
}

public enum HelperVideoStreamNetworkServerError: Error, Equatable, Sendable {
    case invalidPort
}
#endif
