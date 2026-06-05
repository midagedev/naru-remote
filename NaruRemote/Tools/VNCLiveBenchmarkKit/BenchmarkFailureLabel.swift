import Foundation
import NaruRemoteCore

public enum BenchmarkFailurePhase: String, Codable, Equatable, Sendable {
    case streamConnect = "stream-connect"
    case streamFirstFrame = "stream-first-frame"
    case streamStimulus = "stream-stimulus"
    case streamIncremental = "stream-incremental"
    case streamContinuousUpdates = "stream-continuous-updates"
    case continuousProbeConnect = "continuous-probe-connect"
    case continuousProbeFirstFrame = "continuous-probe-first-frame"
    case continuousProbeEnable = "continuous-probe-enable"
    case continuousProbeReceive = "continuous-probe-receive"
}

public enum BenchmarkFailureLabel {
    public static func safeLabel(for error: Error) -> String {
        switch error {
        case RFBNetworkClientError.invalidPort:
            return "invalid-port"
        case RFBNetworkClientError.connectTimedOut:
            return "connect-timeout"
        case RFBNetworkClientError.timedOut:
            return "timeout"
        case RFBNetworkClientError.readTimedOut:
            return "read-timeout"
        case RFBNetworkClientError.incompleteTranscript:
            return "incomplete-transcript"
        case RFBNetworkClientError.connectionFailed:
            return "connection-failed"
        case RFBNetworkClientError.writeTimedOut:
            return "write-timeout"
        case RFBNetworkClientError.writeFailed:
            return "write-failed"
        case RFBNetworkClientError.authenticationRequired:
            return "authentication-required"
        case RFBNetworkClientError.unsupportedSecurityTypes:
            return "unsupported-security-types"
        case RFBNetworkClientError.unsupportedFramebufferEncoding:
            return "unsupported-framebuffer-encoding"
        case RFBNetworkClientError.notConnected:
            return "not-connected"
        case RFBProtocolDecoderError.insufficientData:
            return "protocol-insufficient-data"
        case RFBProtocolDecoderError.invalidProtocolVersion:
            return "invalid-protocol-version"
        case RFBProtocolDecoderError.securityFailed:
            return "security-failed"
        case RFBProtocolDecoderError.unexpectedMessageType:
            return "unexpected-message-type"
        case RFBProtocolDecoderError.truncatedServerCutText:
            return "truncated-server-cuttext"
        case RFBProtocolDecoderError.invalidServerCutTextEncoding:
            return "invalid-server-cuttext-encoding"
        case RFBProtocolDecoderError.malformedExtendedServerCutText:
            return "malformed-extended-server-cuttext"
        case RFBRawFramebufferDecoderError.unsupportedPixelFormat:
            return "unsupported-pixel-format"
        case RFBRawFramebufferDecoderError.unsupportedEncoding:
            return "unsupported-encoding"
        case RFBRawFramebufferDecoderError.rectangleOutOfBounds:
            return "rectangle-out-of-bounds"
        case RFBRawFramebufferDecoderError.insufficientPixelData:
            return "insufficient-pixel-data"
        case RFBRawFramebufferDecoderError.framebufferSizeMismatch:
            return "framebuffer-size-mismatch"
        case RFBRawFramebufferDecoderError.copyRectOutOfBounds:
            return "copyrect-out-of-bounds"
        case RFBRawFramebufferDecoderError.malformedHextile:
            return "malformed-hextile"
        case RFBRawFramebufferDecoderError.invalidDimensions:
            return "invalid-dimensions"
        case RFBRawFramebufferDecoderError.malformedZRLE:
            return "malformed-zrle"
        case RFBRawFramebufferDecoderError.malformedCursor:
            return "malformed-cursor"
        case RFBRawFramebufferDecoderError.malformedTight:
            return "malformed-tight"
        case RFBByteReaderError.insufficientData:
            return "byte-reader-insufficient-data"
        case RFBByteReaderError.negativeRequest:
            return "byte-reader-negative-request"
        case RFBZlibInflateStream.InflateError.initializationFailed:
            return "zlib-initialization-failed"
        case RFBZlibInflateStream.InflateError.inflateFailed:
            return "zlib-inflate-failed"
        case RFBZlibInflateStream.InflateError.streamEndedUnexpectedly:
            return "zlib-stream-ended"
        case RFBTightZlibStreams.StoreError.invalidStreamIndex:
            return "tight-zlib-invalid-stream"
        case RFBVNCAuthenticationError.invalidChallengeLength:
            return "vnc-auth-invalid-challenge"
        case RFBVNCAuthenticationError.encryptionFailed:
            return "vnc-auth-encryption-failed"
        case RFBClientMessageEncodingError.unsupportedFenceFlags:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.fencePayloadTooLarge:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.extendedClipboardPayloadTooLarge:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.zlibCompressionFailed:
            return "client-message-encoding"
        default:
            return "unexpected-error"
        }
    }

    public static func safeLabel(for error: Error, phase: BenchmarkFailurePhase) -> String {
        "\(phase.rawValue)-\(safeLabel(for: error))"
    }
}
