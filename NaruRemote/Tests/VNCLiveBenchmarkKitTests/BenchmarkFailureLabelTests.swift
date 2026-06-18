import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkFailureLabelTests: XCTestCase {
    func testNetworkTimeoutLabelsAreSpecific() {
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBNetworkClientError.connectTimedOut),
            "connect-timeout"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBNetworkClientError.readTimedOut),
            "read-timeout"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBNetworkClientError.writeTimedOut),
            "write-timeout"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBNetworkClientError.continuousUpdatesNotConfirmed),
            "continuous-updates-not-confirmed"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBNetworkClientError.unsupportedBestEffortPointerMask),
            "unsupported-best-effort-pointer-mask"
        )
    }

    func testDecodeAndZlibLabelsStayCatalogOnly() {
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBByteReaderError.insufficientData(requested: 12, available: 4)
            ),
            "byte-reader-insufficient-data"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBZlibInflateStream.InflateError.inflateFailed),
            "zlib-inflate-failed"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: RFBTightZlibStreams.StoreError.invalidStreamIndex),
            "tight-zlib-invalid-stream"
        )
    }

    func testUnknownErrorsRemainCoarse() {
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(for: FixtureError.unknown),
            "unexpected-error"
        )
    }

    func testPhaseLabelsPrefixSafeCatalogLabelOnly() {
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBNetworkClientError.connectionFailed,
                phase: .streamContinuousUpdates
            ),
            "stream-continuous-updates-connection-failed"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBNetworkClientError.writeTimedOut,
                phase: .continuousProbeEnable
            ),
            "continuous-probe-enable-write-timeout"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBNetworkClientError.continuousUpdatesNotConfirmed,
                phase: .streamContinuousUpdates
            ),
            "stream-continuous-updates-continuous-updates-not-confirmed"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBNetworkClientError.connectionFailed,
                phase: .streamStimulus
            ),
            "stream-stimulus-connection-failed"
        )
        XCTAssertEqual(
            BenchmarkFailureLabel.safeLabel(
                for: RFBNetworkClientError.writeTimedOut,
                phase: .pointerHoverSend
            ),
            "pointer-hover-send-write-timeout"
        )
    }
}

private enum FixtureError: Error {
    case unknown
}
