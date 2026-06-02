import Foundation
import NaruRemoteApp
import NaruRemoteCore

/// XCUITest screenshot hook — selects a synthetic
/// `NaruRemoteAppSnapshot` (and any post-init model mutations that
/// don't fit on the snapshot value type) so the audit harness
/// (`UXAuditScreenshotsUITests`) can drive states the live persistence
/// path cannot reach without a real RFB session.
///
/// The fixture is selected by the `NARU_TEST_FIXTURE_SNAPSHOT` launch
/// environment variable.  When the variable is unset (production) the
/// hook is fully inert: `loadFixtureSnapshot()` returns `nil`, the
/// shell builds a fresh empty model the same way it always has, and
/// `applyFixturePostInitMutations()` short-circuits.
///
/// All fixtures reuse existing `NaruRemoteCore` value types — we do
/// not fabricate new model types for the audit (constraint per
/// `chore/ux-02-audit-fixture-richness`).
enum UXAuditFixtureToken: String {
    case diagnosticsPopulated = "diagnostics-populated"
    case diagnosticErrorDNS = "diagnostic-error-dns"
    case incomingClipboard = "incoming-clipboard"
    case sidebarWithVerdicts = "sidebar-with-verdicts"
    /// Active session showing a real 16:9 remote framebuffer — drives
    /// the screen-first viewport (spec 003 FR-001) so the audit can
    /// confirm the remote screen renders at the server's true aspect
    /// ratio instead of a hardcoded 4:3 box.
    case sessionActiveWidescreen = "session-active-widescreen"

    static func current() -> UXAuditFixtureToken? {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_FIXTURE_SNAPSHOT"],
              !raw.isEmpty
        else { return nil }
        return UXAuditFixtureToken(rawValue: raw)
    }
}

enum UXAuditFixtures {
    /// Builds the snapshot for the currently-selected fixture token,
    /// or `nil` when the env var is unset / unrecognised.  The shell
    /// passes the snapshot to `NaruRemoteAppModel(snapshot:)` so the
    /// model lands in the desired UI state on first paint.
    static func loadFixtureSnapshot() -> NaruRemoteAppSnapshot? {
        guard let token = UXAuditFixtureToken.current() else {
            return nil
        }
        switch token {
        case .diagnosticsPopulated:
            return diagnosticsPopulatedSnapshot()
        case .diagnosticErrorDNS:
            return diagnosticErrorDNSSnapshot()
        case .incomingClipboard:
            return incomingClipboardSnapshot()
        case .sidebarWithVerdicts:
            return sidebarWithVerdictsSnapshot()
        case .sessionActiveWidescreen:
            return sessionActiveWidescreenSnapshot()
        }
    }

    /// Some screen states (notably the incoming-clipboard banner)
    /// live on the model directly rather than on
    /// `NaruRemoteAppSnapshot`.  Apply those after the model is
    /// constructed.  No-op when the env var is unset.
    @MainActor
    static func applyFixturePostInitMutations(to model: NaruRemoteAppModel) {
        guard let token = UXAuditFixtureToken.current() else {
            return
        }
        switch token {
        case .incomingClipboard:
            // Calling `recordIncomingClipboard` is the canonical path
            // a real `ServerCutText` would take through the model —
            // it sets `pendingIncomingClipboard` to a fresh review.
            model.recordIncomingClipboard(
                "Hello from the remote computer — this is a clipboard payload that arrived from the VNC server."
            )
        case .sessionActiveWidescreen:
            // Seed a connection-quality bucket so the header quality
            // chip renders in the capture — the production estimator is
            // fed by a live latency stream the fixture can't drive.
            model.seedConnectionQualityForTesting(.good)
        case .diagnosticsPopulated,
             .diagnosticErrorDNS,
             .sidebarWithVerdicts:
            // All snapshot-driven; no post-init mutation needed.
            break
        }
    }

    // MARK: - Fixture builders

    private static func diagnosticsPopulatedSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 4),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Host resolved",
                    safeDetail: "MagicDNS returned a private address.",
                    timestamp: fixedDate(offsetSeconds: 1)
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .passed,
                    safeTitle: "VNC port open",
                    safeDetail: "TCP connection to the VNC port succeeded.",
                    timestamp: fixedDate(offsetSeconds: 2)
                ),
                DiagnosticStageResult(
                    stage: .rfbHandshake,
                    status: .passed,
                    safeTitle: "RFB handshake complete",
                    safeDetail: "Server speaks a compatible RFB version.",
                    timestamp: fixedDate(offsetSeconds: 3)
                ),
                DiagnosticStageResult(
                    stage: .authentication,
                    status: .running,
                    safeTitle: "Authenticating",
                    safeDetail: "Negotiating credentials with the VNC server.",
                    timestamp: fixedDate(offsetSeconds: 4)
                )
            ]
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run
        )
    }

    private static func diagnosticErrorDNSSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 2),
            stages: [
                DiagnosticMessageCatalog.failure(
                    for: .dns,
                    timestamp: fixedDate(offsetSeconds: 2)
                )
            ]
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run
        )
    }

    /// Multi-profile sidebar snapshot whose `lastDiagnosticVerdict`
    /// dict pre-populates one of each verdict color so the audit
    /// screenshot exercises the leading status-dot palette (UX
    /// punch-list #109).  The four profiles deliberately mirror the
    /// `runSidebarMultipleProfiles` XCUITest seed (Studio Mac /
    /// Office Linux / Home NUC / Public test) so a reviewer can
    /// diff the with-verdicts capture against the gray-dot capture
    /// without mental remapping.
    private static func sidebarWithVerdictsSnapshot() -> NaruRemoteAppSnapshot {
        let studio = try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            displayName: "Studio Mac",
            host: "studio.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let office = try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            displayName: "Office Linux",
            host: "office.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let home = try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
            displayName: "Home NUC",
            host: "10.0.0.42",
            hostKind: .privateAddress
        )
        let publicTest = try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!,
            displayName: "Public test",
            host: "203.0.113.5",
            hostKind: .advancedManualPublicEndpoint
        )

        let verdicts: [ConnectionProfile.ID: DiagnosticVerdict] = [
            studio.id: .passed,
            office.id: .warning,
            home.id: .failed
            // `publicTest.id` intentionally omitted so it renders as
            // `.unknown` (gray) — covers the "no diagnostic ever
            // run" path while the other three exercise green / amber
            // / red.
        ]
        let previews: [ConnectionProfile.ID: ProfilePreviewThumbnail] = [
            studio.id: gradientPreview(
                top: RFBColor(red: 0x16, green: 0x2A, blue: 0x3A),
                bottom: RFBColor(red: 0x1B, green: 0x72, blue: 0x6F)
            ),
            home.id: gradientPreview(
                top: RFBColor(red: 0x32, green: 0x22, blue: 0x48),
                bottom: RFBColor(red: 0x8E, green: 0x3D, blue: 0x55)
            )
        ]

        return NaruRemoteAppSnapshot(
            profiles: [studio, office, home, publicTest],
            selectedProfileID: studio.id,
            profilePreviews: previews,
            lastDiagnosticVerdict: verdicts
        )
    }

    private static func incomingClipboardSnapshot() -> NaruRemoteAppSnapshot {
        // Need an .active session so the dock + banner are mounted
        // in their post-connect form (the banner sits inside the
        // detail safeAreaInset and renders whenever
        // `pendingIncomingClipboard != nil`, but the surrounding
        // layout reads more naturally with a live session).
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session
        )
    }

    /// Active session carrying a 16:9 framebuffer so the session
    /// viewport renders the remote screen at the server's true aspect
    /// ratio (spec 003 FR-001 — screen-first).  A real desktop is
    /// 16:9 / 16:10; before this change the container hardcoded 4:3
    /// and double-letterboxed widescreen frames into a small box.  The
    /// framebuffer is a solid fill (the public `RFBRawFramebuffer`
    /// init only takes one color) — the point of the fixture is the
    /// container *shape*, which a solid wide rectangle makes obvious.
    private static func sessionActiveWidescreenSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        // 1600×900 = 16:9.  Mid-slate fill so it reads as a real
        // screen against the dark container, not an empty black box.
        let framebuffer = RFBRawFramebuffer(
            width: 1600,
            height: 900,
            fill: RFBColor(red: 0x1E, green: 0x2A, blue: 0x38)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: framebuffer
        )
    }

    // MARK: - Shared building blocks

    /// Stable-ID profile so multiple-fixture screenshots share the
    /// same selection target if the test suite ever cross-references
    /// them.  `try!` is fine here — the hard-coded values satisfy
    /// `ConnectionProfile`'s validation.
    private static func sampleProfile() -> ConnectionProfile {
        // swiftlint:disable:next force_try
        try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            displayName: "Studio Mac",
            host: "studio.tailnet.ts.net",
            port: 5900,
            hostKind: .magicDNS
        )
    }

    /// Fixed reference date so screenshots are pixel-stable across
    /// runs (no "seconds ago" labels jitter the diff).
    private static func fixedDate(offsetSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offsetSeconds)
    }

    private static func gradientPreview(
        top: RFBColor,
        bottom: RFBColor,
        width: Int = 32,
        height: Int = 20
    ) -> ProfilePreviewThumbnail {
        var pixels: [RFBColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let blend = Double(y) / Double(max(height - 1, 1))
            for x in 0..<width {
                let stripe = (x / 4) % 2 == 0
                let red = lerp(top.red, bottom.red, blend)
                let green = lerp(top.green, bottom.green, blend)
                let blue = lerp(top.blue, bottom.blue, blend)
                pixels.append(
                    RFBColor(
                        red: stripe ? red : UInt8(max(Int(red) - 18, 0)),
                        green: stripe ? green : UInt8(max(Int(green) - 18, 0)),
                        blue: stripe ? blue : UInt8(max(Int(blue) - 18, 0))
                    )
                )
            }
        }
        return ProfilePreviewThumbnail(
            width: width,
            height: height,
            sourceWidth: 1600,
            sourceHeight: 1000,
            capturedAt: fixedDate(offsetSeconds: 7),
            pixels: pixels
        )
    }

    private static func lerp(_ start: UInt8, _ end: UInt8, _ blend: Double) -> UInt8 {
        UInt8((Double(start) + (Double(end) - Double(start)) * blend).rounded())
    }
}
