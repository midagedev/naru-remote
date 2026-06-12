import XCTest
@testable import NaruRemoteCore

#if canImport(Network)
import Network

final class NaruLowLatencyTCPParametersTests: XCTestCase {
    func testMakeEnablesTCPNoDelayForInteractiveStreams() throws {
        let parameters = NaruLowLatencyTCPParameters.make()
        let tcpOptions = try XCTUnwrap(
            parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
        )

        XCTAssertTrue(tcpOptions.noDelay)
    }
}
#endif
