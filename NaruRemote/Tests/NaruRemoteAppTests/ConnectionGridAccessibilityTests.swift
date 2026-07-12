import NaruRemoteCore
import XCTest
@testable import NaruRemoteApp

final class ConnectionGridAccessibilityTests: XCTestCase {
    func testPublicEndpointCardAnnouncesWarningAndSecurityHint() {
        let card = ConnectionGridCard(
            id: UUID(),
            displayName: "Public Mac",
            endpoint: "example.com:5900",
            hostKind: .advancedManualPublicEndpoint,
            verdict: .unknown,
            isSelected: false
        )

        XCTAssertEqual(
            ConnectionGridView.cardAccessibilityLabel(for: card),
            "Public Mac, example.com:5900, Public address, advanced public endpoint warning, reachability unknown, helper video not configured, VNC visual fallback"
        )
        XCTAssertEqual(
            ConnectionGridView.cardAccessibilityHint(for: card),
            "Review the public address and its security before connecting"
        )
    }

    func testPrivateEndpointCardUsesOrdinaryOpenHint() {
        let card = ConnectionGridCard(
            id: UUID(),
            displayName: "Studio Mac",
            endpoint: "studio.tailnet.ts.net:5900",
            hostKind: .magicDNS,
            verdict: .unknown,
            isSelected: false
        )

        XCTAssertTrue(
            ConnectionGridView.cardAccessibilityLabel(for: card)
                .contains("MagicDNS address")
        )
        XCTAssertEqual(
            ConnectionGridView.cardAccessibilityHint(for: card),
            "Connect to this saved computer"
        )
    }
}
