import NaruRemoteCore
import SwiftUI
import XCTest
@testable import NaruRemoteApp

final class SessionDiagnosticCornerStateTests: XCTestCase {
    func testNilAndPendingSessionMappingsAreConciseAndTyped() {
        assertState(
            sessionState: nil,
            quality: .poor,
            primary: "Not connected",
            secondary: nil,
            symbol: "circle.dashed",
            tone: .neutral,
            accessibilityValue: "Not connected"
        )
        assertState(
            sessionState: .connecting,
            quality: .poor,
            primary: "Connecting",
            secondary: nil,
            symbol: "arrow.triangle.2.circlepath",
            tone: .progress,
            accessibilityValue: "Connecting"
        )
        assertState(
            sessionState: .authenticating,
            quality: .good,
            primary: "Authenticating",
            secondary: nil,
            symbol: "lock.shield",
            tone: .progress,
            accessibilityValue: "Authenticating"
        )
    }

    func testActiveSessionMapsEveryCoarseQualityWithoutRelyingOnColor() {
        assertState(
            sessionState: .active,
            quality: .unknown,
            primary: "Connected",
            secondary: "Measuring",
            symbol: "checkmark.circle",
            tone: .progress,
            accessibilityValue: "Connected, connection quality not measured yet"
        )
        assertState(
            sessionState: .active,
            quality: .good,
            primary: "Connected",
            secondary: "Good",
            symbol: "checkmark.circle.fill",
            tone: .healthy,
            accessibilityValue: "Connected, connection quality good"
        )
        assertState(
            sessionState: .active,
            quality: .fair,
            primary: "Connected",
            secondary: "Fair",
            symbol: "exclamationmark.circle.fill",
            tone: .warning,
            accessibilityValue: "Connected, connection quality fair"
        )
        assertState(
            sessionState: .active,
            quality: .poor,
            primary: "Connected",
            secondary: "Poor",
            symbol: "exclamationmark.triangle.fill",
            tone: .critical,
            accessibilityValue: "Connected, connection quality poor"
        )
    }

    func testReconnectDegradedFailedAndClosedMappingsUseSafeRowsOnly() {
        let safeFailure = DiagnosticSummaryRow(
            id: "tcp-failed",
            stage: "tcpConnect",
            status: "failed",
            title: "Remote service unavailable",
            detail: "The private connection could not be opened."
        )
        let rows = [safeFailure]

        assertState(
            sessionState: .reconnecting(attempt: 2, of: 3),
            quality: .poor,
            rows: rows,
            primary: "Reconnecting",
            secondary: "2/3",
            symbol: "arrow.clockwise",
            tone: .warning,
            accessibilityValue: "Reconnecting, attempt 2 of 3"
        )
        assertState(
            sessionState: .degraded,
            quality: .poor,
            rows: rows,
            primary: "Degraded",
            secondary: safeFailure.title,
            symbol: "exclamationmark.triangle.fill",
            tone: .warning,
            accessibilityValue: "Connection degraded, \(safeFailure.title), \(safeFailure.detail)"
        )
        assertState(
            sessionState: .failed,
            quality: .good,
            rows: rows,
            primary: "Failed",
            secondary: safeFailure.title,
            symbol: "xmark.octagon.fill",
            tone: .critical,
            accessibilityValue: "Connection failed, \(safeFailure.title), \(safeFailure.detail)"
        )
        assertState(
            sessionState: .closed,
            quality: .unknown,
            rows: rows,
            primary: "Disconnected",
            secondary: "Last: \(safeFailure.title)",
            symbol: "rectangle.portrait.and.arrow.right",
            tone: .neutral,
            accessibilityValue: "Disconnected, \(safeFailure.title), \(safeFailure.detail)"
        )
    }

    func testRawSessionMessagesNeverEnterPresentationState() {
        let privateSentinel = "private-host.example:5900 raw socket error"
        let session = RemoteSession(
            profileID: UUID(),
            state: .failed,
            hudMessage: privateSentinel,
            lastError: privateSentinel
        )
        let state = SessionDiagnosticCornerState(
            session: session,
            connectionQuality: .poor,
            rows: []
        )

        let rendered = [
            state.primaryText,
            state.secondaryText ?? "",
            state.accessibilityValue,
        ].joined(separator: " ")
        XCTAssertFalse(rendered.contains(privateSentinel))
        XCTAssertEqual(state.accessibilityValue, "Connection failed")
    }

    func testCapsuleHasMinimumPlatformHitTargetAndCompactWidthCap() {
        XCTAssertGreaterThanOrEqual(SessionDiagnosticCornerView.minimumHitDimension, 44)
        XCTAssertGreaterThan(
            SessionDiagnosticCornerView.maximumCompactWidth,
            SessionDiagnosticCornerView.minimumHitDimension
        )
        XCTAssertLessThanOrEqual(SessionDiagnosticCornerView.maximumCompactWidth, 280)
    }

    private func assertState(
        sessionState: RemoteSessionState?,
        quality: ConnectionQuality,
        rows: [DiagnosticSummaryRow] = [],
        primary: String,
        secondary: String?,
        symbol: String,
        tone: SessionDiagnosticCornerState.Tone,
        accessibilityValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let session = sessionState.map {
            RemoteSession(profileID: UUID(), state: $0)
        }
        let state = SessionDiagnosticCornerState(
            session: session,
            connectionQuality: quality,
            rows: rows
        )

        XCTAssertEqual(state.primaryText, primary, file: file, line: line)
        XCTAssertEqual(state.secondaryText, secondary, file: file, line: line)
        XCTAssertEqual(state.systemImage, symbol, file: file, line: line)
        XCTAssertEqual(state.tone, tone, file: file, line: line)
        XCTAssertEqual(state.accessibilityValue, accessibilityValue, file: file, line: line)
        XCTAssertEqual(state.rows, rows, file: file, line: line)
    }
}
