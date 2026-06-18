import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapeStimulusEnvironmentTests: XCTestCase {
    func testMakeKeepsOnlyLaunchAllowlistAndStimulusHints() {
        let environment = BenchmarkStreamShapeStimulusEnvironment.make(
            parent: [
                "PATH": "/usr/bin",
                "HOME": "/Users/example",
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PASSWORD": "secret",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_STIMULUS_COMMAND": "secret command",
                "NARU_LIVE_STIMULUS_VISUAL_FRESHNESS_FILE": "/tmp/naru-freshness.jsonl",
                "UNRELATED_SECRET": "secret"
            ],
            durationSeconds: "7.25",
            frameIntervalSeconds: "0.0833",
            profileLabel: "local-low-latency",
            transportMode: "request-response"
        )

        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["HOME"], "/Users/example")
        XCTAssertEqual(environment["NARU_LIVE_STIMULUS_DURATION_SECONDS"], "7.25")
        XCTAssertEqual(environment["NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS"], "0.0833")
        XCTAssertEqual(environment["NARU_LIVE_STIMULUS_PROFILE_LABEL"], "local-low-latency")
        XCTAssertEqual(environment["NARU_LIVE_STIMULUS_TRANSPORT_MODE"], "request-response")
        XCTAssertEqual(environment["NARU_LIVE_STIMULUS_VISUAL_FRESHNESS_FILE"], "/tmp/naru-freshness.jsonl")
        XCTAssertNil(environment["NARU_LIVE_MAC_HOST"])
        XCTAssertNil(environment["NARU_LIVE_MAC_PASSWORD"])
        XCTAssertNil(environment["NARU_LIVE_MAC_PORT"])
        XCTAssertNil(environment["NARU_LIVE_STIMULUS_COMMAND"])
        XCTAssertNil(environment["UNRELATED_SECRET"])
    }

    func testCommandKeyIsStableForCliContract() {
        XCTAssertEqual(
            BenchmarkStreamShapeStimulusEnvironment.commandKey,
            "NARU_LIVE_STIMULUS_COMMAND"
        )
        XCTAssertEqual(
            BenchmarkStreamShapeStimulusEnvironment.frameIntervalKey,
            "NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS"
        )
    }
}
