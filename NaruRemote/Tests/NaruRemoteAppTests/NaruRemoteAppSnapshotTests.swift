import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class NaruRemoteAppSnapshotTests: XCTestCase {
    func testSnapshotUsesSelectedProfileForTitleAndSubtitle() throws {
        let first = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net", port: 5901)

        let snapshot = NaruRemoteAppSnapshot(
            profiles: [first, second],
            selectedProfileID: second.id
        )

        XCTAssertEqual(snapshot.title, "Desk")
        XCTAssertEqual(snapshot.subtitle, "desk.tailnet.ts.net:5901")
        XCTAssertEqual(snapshot.selectedProfile, second)
    }

    func testSnapshotFallsBackToFirstProfileWhenSelectionIsStale() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")

        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: UUID()
        )

        XCTAssertEqual(snapshot.selectedProfile, profile)
        XCTAssertEqual(snapshot.title, "Studio")
    }

    func testInputStatusKeepsUnknownPasteHonest() {
        let sessionID = UUID()
        let draftID = UUID()
        let attempt = TextInjectionAttempt(
            draftID: draftID,
            sessionID: sessionID,
            path: .vncClipboardPaste,
            status: .unknown,
            remoteClipboardRestore: .unsupported,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )

        let snapshot = NaruRemoteAppSnapshot(latestInjectionAttempt: attempt)

        XCTAssertEqual(snapshot.inputStatusText, "Paste command sent; remote app confirmation unavailable.")
    }

    func testDiagnosticRowsExposeSafeStageText() {
        let profileID = UUID()
        let run = ConnectionDiagnosticRun(
            profileID: profileID,
            stages: [
                DiagnosticMessageCatalog.failure(for: .dns)
            ]
        )

        let snapshot = NaruRemoteAppSnapshot(diagnosticRun: run)

        XCTAssertEqual(snapshot.diagnosticRows.count, 1)
        XCTAssertEqual(snapshot.diagnosticRows.first?.stage, "dns")
        XCTAssertEqual(snapshot.diagnosticRows.first?.status, "failed")
        XCTAssertEqual(snapshot.diagnosticRows.first?.title, "MagicDNS did not resolve")
    }

    func testDiagnosticRowsUseStableUniqueIDsForRepeatedStages() {
        let profileID = UUID()
        let first = DiagnosticMessageCatalog.failure(for: .tcp)
        let second = DiagnosticMessageCatalog.failure(for: .tcp)
        let run = ConnectionDiagnosticRun(profileID: profileID, stages: [first, second])

        let snapshot = NaruRemoteAppSnapshot(diagnosticRun: run)

        XCTAssertEqual(snapshot.diagnosticRows.count, 2)
        XCTAssertNotEqual(snapshot.diagnosticRows[0].id, snapshot.diagnosticRows[1].id)
    }

    func testPiPWatchStatusWaitsForFirstFrameBeforeSessionIsActive() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .connecting)
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP after first frame")
    }

    func testPiPWatchStatusWaitsForFirstFrameEvenWhenSessionIsActive() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP after first frame")
    }

    func testPiPWatchStatusHonorsProfileOptOut() throws {
        let profile = try ConnectionProfile(
            displayName: "Sensitive Desk",
            host: "sensitive.tailnet.ts.net",
            allowsPiPWatch: false
        )
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP disabled for profile")
    }

    func testPiPWatchStatusShowsWatchingState() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipWatchSession = PiPWatchSession(sessionID: session.id, state: .watching)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            pipWatchSession: pipWatchSession
        )

        XCTAssertTrue(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "Watching in PiP")
    }

    func testConnectionGridCardsExposeProfileAndVerdictState() throws {
        let studio = try ConnectionProfile(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let publicHost = try ConnectionProfile(
            displayName: "Public Test",
            host: "203.0.113.5",
            hostKind: .advancedManualPublicEndpoint
        )
        let preview = ProfilePreviewThumbnail(
            width: 1,
            height: 1,
            sourceWidth: 2,
            sourceHeight: 2,
            capturedAt: Date(timeIntervalSince1970: 100),
            pixels: [RFBColor(red: 1, green: 2, blue: 3)]
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [studio, publicHost],
            selectedProfileID: publicHost.id,
            profilePreviews: [studio.id: preview],
            lastDiagnosticVerdict: [studio.id: .passed]
        )

        XCTAssertEqual(snapshot.connectionGridCards.count, 2)
        XCTAssertEqual(snapshot.connectionGridCards[0].displayName, "Studio")
        XCTAssertEqual(snapshot.connectionGridCards[0].endpoint, "studio.tailnet.ts.net:5900")
        XCTAssertEqual(snapshot.connectionGridCards[0].preview, preview)
        XCTAssertEqual(snapshot.connectionGridCards[0].verdict, .passed)
        XCTAssertFalse(snapshot.connectionGridCards[0].isSelected)
        XCTAssertEqual(snapshot.connectionGridCards[1].hostKind, .advancedManualPublicEndpoint)
        XCTAssertNil(snapshot.connectionGridCards[1].preview)
        XCTAssertEqual(snapshot.connectionGridCards[1].verdict, .unknown)
        XCTAssertTrue(snapshot.connectionGridCards[1].isSelected)
    }
}
