import Foundation
import NaruRemoteCore
import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkTextKeystrokeProbeReportTests: XCTestCase {
    func testPayloadUsageDescriptionListsStableLabels() {
        XCTAssertEqual(
            BenchmarkTextKeystrokeProbePayload.usageDescription,
            "ascii|latin1|unicode-hangul"
        )
    }

    func testUnicodeHangulPayloadClassifiesAsUnicodeKeysymProbe() {
        let result = TextKeystrokeTranscoder.transcode(
            BenchmarkTextKeystrokeProbePayload.unicodeHangul.probeText
        )

        XCTAssertTrue(result.canEmit)
        XCTAssertEqual(result.payloadEncoding, .utf8ExtensionRequired)
        XCTAssertTrue(result.usesUnicodeKeysyms)
        XCTAssertEqual(
            BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: result.events.count * 2),
            .oneToFive
        )
    }

    func testReportJSONOmitsRawTextAndKeysyms() throws {
        let result = TextKeystrokeTranscoder.transcode(
            BenchmarkTextKeystrokeProbePayload.unicodeHangul.probeText
        )
        let report = BenchmarkTextKeystrokeProbeReport(
            status: .sent,
            payload: .unicodeHangul,
            networkConditionProfile: .constrainedCellular,
            payloadEncoding: result.payloadEncoding,
            usesUnicodeKeysyms: result.usesUnicodeKeysyms,
            eventCountBucket: .bucket(for: result.events.count * 2),
            connectStatus: .passed,
            firstFrameStatus: .passed,
            transcodeStatus: .passed,
            sendStatus: .passed,
            failureLabel: nil
        )

        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"unicode-hangul\""))
        XCTAssertTrue(json.contains("\"utf8ExtensionRequired\""))
        XCTAssertTrue(json.contains("\"constrained-cellular\""))
        XCTAssertFalse(json.contains(BenchmarkTextKeystrokeProbePayload.unicodeHangul.probeText))
        XCTAssertFalse(json.contains("0x"))
        XCTAssertFalse(json.contains("D55C"))
        XCTAssertFalse(json.contains("AE00"))
    }

    func testEventCountBucketsUseCoarseFixedBands() {
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 0), .zero)
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 1), .oneToFive)
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 5), .oneToFive)
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 6), .sixToTwenty)
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 20), .sixToTwenty)
        XCTAssertEqual(BenchmarkTextKeystrokeProbeEventCountBucket.bucket(for: 21), .overTwenty)
    }
}
