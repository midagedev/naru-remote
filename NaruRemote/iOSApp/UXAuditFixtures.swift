#if DEBUG
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
    /// Active session with a stale Compose send result, used to reproduce
    /// the keyboard-safe-area transition that can happen after the next
    /// focused Korean/CJK syllable clears that result.
    case sessionActiveComposeConfirmationUnavailable = "session-active-compose-confirmation-unavailable"
    /// Connecting session that receives its first framebuffer only after
    /// Compose focus is active.  Used to reproduce the reported
    /// "first Korean syllable, then live session starts, keyboard freezes"
    /// transition without a real socket.
    case sessionConnectingDelayedFirstFrame = "session-connecting-delayed-first-frame"
    /// A session in the degraded state, so the health affordance renders its
    /// warning form. Spec 033 FR-004 makes the healthy form silent, and a
    /// screenshot gate that can only reach the silent one proves half a rule.
    case sessionDegraded = "session-degraded"
    /// Active session in trackpad mode with a server-provided cursor
    /// shape so screenshots cover the "real remote cursor" overlay path.
    case sessionActiveTrackpadCursor = "session-active-trackpad-cursor"
    /// App Store marketing states. These differ from the audit fixtures
    /// above on purpose: an audit capture wants every badge and failure
    /// path in one frame, a store capture wants one healthy, legible
    /// story per slot. Keeping them as separate tokens means tightening
    /// a store shot never weakens an audit shot's coverage.
    case storeConnectionGrid = "store-connection-grid"
    /// Live session on the store desktop — slot 2 (bare remote screen)
    /// and slot 4 (function row expanded over it).
    case storeSessionActive = "store-session-active"
    /// Active session whose Compose draft already holds Korean text, so
    /// the store slot for local composition shows the real editor with
    /// real Hangul instead of depending on simulator IME typing.
    case storeSessionKoreanCompose = "store-session-korean-compose"
    /// Diagnostics with every stage passed through first frame — the
    /// audit fixture deliberately leaves authentication `.running`.
    case storeDiagnosticsPassed = "store-diagnostics-passed"

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
        case .sessionActiveComposeConfirmationUnavailable:
            return sessionActiveComposeConfirmationUnavailableSnapshot()
        case .sessionConnectingDelayedFirstFrame:
            return sessionConnectingDelayedFirstFrameSnapshot()
        case .sessionDegraded:
            return sessionDegradedSnapshot()
        case .sessionActiveTrackpadCursor:
            return sessionActiveWidescreenSnapshot(serverCursor: serverCursorArrow())
        case .storeConnectionGrid:
            return storeConnectionGridSnapshot()
        case .storeSessionActive:
            return storeSessionActiveSnapshot()
        case .storeSessionKoreanCompose:
            return storeSessionKoreanComposeSnapshot()
        case .storeDiagnosticsPassed:
            return storeDiagnosticsPassedSnapshot()
        }
    }

    /// XCUITest E2E hook — seed one live-test profile directly from
    /// the target app's launch environment.  This avoids cross-sandbox
    /// file sharing on physical devices while keeping secrets out of
    /// source: only the credential reference is stored on the profile;
    /// the password still flows through `NARU_TEST_INJECT_KEYCHAIN_*`.
    static func loadSeedProfileSnapshot() -> NaruRemoteAppSnapshot? {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["NARU_TEST_SEED_PROFILE_HOST"]?.trimmedNonEmpty else {
            return nil
        }

        let id = env["NARU_TEST_SEED_PROFILE_ID"].flatMap(UUID.init(uuidString:))
            ?? UUID(uuidString: "00000000-0000-0000-0000-00000000E2E0")!
        let displayName = env["NARU_TEST_SEED_PROFILE_NAME"]?.trimmedNonEmpty ?? "Physical E2E Mac"
        let port = env["NARU_TEST_SEED_PROFILE_PORT"].flatMap(Int.init) ?? 5900
        let hostKind = env["NARU_TEST_SEED_PROFILE_HOST_KIND"]
            .flatMap(ConnectionProfile.HostKind.init(rawValue:)) ?? .privateAddress
        let credentialRef = env["NARU_TEST_SEED_PROFILE_CREDENTIAL_REF"]?.trimmedNonEmpty
        let helperVideo = Self.seedHelperVideoConfiguration(from: env)

        guard let profile = try? ConnectionProfile(
            id: id,
            displayName: displayName,
            host: host,
            port: port,
            credentialRef: credentialRef,
            hostKind: hostKind,
            helperVideo: helperVideo
        ) else {
            return nil
        }

        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id
        )
    }

    private static func seedHelperVideoConfiguration(
        from env: [String: String]
    ) -> HelperVideoConnectionConfiguration? {
        guard env.isTruthy("NARU_TEST_SEED_HELPER_VIDEO_ENABLED") else {
            return nil
        }

        guard let pairingSecretRef = env["NARU_TEST_SEED_HELPER_VIDEO_SECRET_REF"]?.trimmedNonEmpty,
              let pairingFingerprint = env["NARU_TEST_SEED_HELPER_VIDEO_PAIRING_FINGERPRINT"]?.trimmedNonEmpty
        else {
            preconditionFailure(
                "NARU_TEST_SEED_HELPER_VIDEO_ENABLED requires " +
                    "NARU_TEST_SEED_HELPER_VIDEO_SECRET_REF and " +
                    "NARU_TEST_SEED_HELPER_VIDEO_PAIRING_FINGERPRINT"
            )
        }

        return HelperVideoConnectionConfiguration(
            isEnabled: true,
            pairingSecretRef: pairingSecretRef,
            pairingFingerprint: pairingFingerprint
        )
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
        case .sessionActiveComposeConfirmationUnavailable:
            model.seedConnectionQualityForTesting(.good)
        case .sessionConnectingDelayedFirstFrame:
            model.seedConnectionQualityForTesting(.good)
        case .sessionDegraded:
            // A measured-but-poor link, which is the tone the warning form
            // exists for.
            model.seedConnectionQualityForTesting(.poor)
        case .sessionActiveTrackpadCursor:
            // Same active-session surface, but start in trackpad mode so
            // the cursor overlay uses the server cursor shape seeded on
            // the snapshot.
            model.seedConnectionQualityForTesting(.good)
            model.togglePointerControlMode()
        case .storeSessionActive,
             .storeSessionKoreanCompose:
            model.seedConnectionQualityForTesting(.good)
        case .diagnosticsPopulated,
             .diagnosticErrorDNS,
             .sidebarWithVerdicts,
             .storeConnectionGrid,
             .storeDiagnosticsPassed:
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

    /// Multi-profile grid snapshot whose diagnostic verdicts and
    /// launch reachability states are pre-populated so the audit
    /// screenshot exercises every status badge plus mixed preview /
    /// placeholder cards.
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
        let travel = try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!,
            displayName: "Travel Mac",
            host: "100.64.12.20",
            hostKind: .privateAddress
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
        let reachability: [ConnectionProfile.ID: ProfileReachabilityState] = [
            studio.id: .reachable,
            office.id: .checking,
            home.id: .unreachable(failedStage: .tcp),
            publicTest.id: .needsPassword
            // `travel.id` intentionally omitted so it renders as
            // `.unknown` and the capture covers all five launch
            // reachability states.
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
            profiles: [studio, office, home, publicTest, travel],
            selectedProfileID: studio.id,
            profilePreviews: previews,
            profileReachability: reachability,
            lastDiagnosticVerdict: verdicts
        )
    }

    // MARK: - App Store marketing fixtures

    /// Store slot 1 — the host list as a healthy home screen: saved
    /// computers, every one reachable with a passing verdict and a real
    /// (downscaled) desktop preview.
    private static func storeConnectionGridSnapshot() -> NaruRemoteAppSnapshot {
        // Eight machines: a 13" iPad fits four per row, and four profiles
        // left the store capture as one row above half an empty screen.
        // Each entry carries the name its own preview draws, so a grid of
        // cards reads as a grid of machines instead of one screenshot
        // pasted eight times — a channel tint alone is invisible at card
        // size.
        let machines: [(name: String, host: String, kind: ConnectionProfile.HostKind, screenName: String, status: String, tint: (Double, Double, Double))] = [
            ("Studio Mac", "studio.tailnet.ts.net", .magicDNS, "STUDIO MAC", "BUILD PASSED", (1.00, 1.00, 1.00)),
            ("MacBook Pro", "macbook-pro.tailnet.ts.net", .magicDNS, "MACBOOK PRO", "TESTS PASSED", (0.88, 0.98, 1.10)),
            ("Office Linux", "office.tailnet.ts.net", .magicDNS, "OFFICE LINUX", "DOCKER READY", (0.84, 1.06, 0.90)),
            ("Home NUC", "10.0.0.42", .privateAddress, "HOME NUC", "BACKUP DONE", (1.12, 0.92, 1.06)),
            ("Travel Mac", "travel.tailnet.ts.net", .magicDNS, "TRAVEL MAC", "SYNC DONE", (0.96, 1.02, 0.94)),
            ("Build Server", "build.tailnet.ts.net", .magicDNS, "BUILD SERVER", "DEPLOY READY", (0.90, 0.94, 1.12)),
            ("Lab Mini", "10.0.0.51", .privateAddress, "LAB MINI", "IDLE 2 JOBS", (1.06, 1.00, 0.92)),
            ("Media NUC", "media.tailnet.ts.net", .magicDNS, "MEDIA NUC", "RENDER DONE", (1.00, 0.94, 1.10))
        ]

        var profiles: [ConnectionProfile] = []
        var previews: [ConnectionProfile.ID: ProfilePreviewThumbnail] = [:]
        var reachability: [ConnectionProfile.ID: ProfileReachabilityState] = [:]
        var verdicts: [ConnectionProfile.ID: DiagnosticVerdict] = [:]

        for (index, machine) in machines.enumerated() {
            // Fixed IDs keep the capture stable across runs.
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000C%X", index + 1))!
            // swiftlint:disable:next force_try
            let profile = try! ConnectionProfile(
                id: id,
                displayName: machine.name,
                host: machine.host,
                hostKind: machine.kind
            )
            profiles.append(profile)
            previews[id] = desktopPreview(
                machineName: machine.screenName,
                status: machine.status,
                tint: machine.tint
            )
            // Every card healthy: the audit fixture owns the failed /
            // unreachable / manual-public-endpoint badges, and a red card in
            // slot 1 would advertise a broken connection.
            reachability[id] = .reachable
            verdicts[id] = .passed
        }

        return NaruRemoteAppSnapshot(
            profiles: profiles,
            selectedProfileID: nil,
            profilePreviews: previews,
            profileReachability: reachability,
            lastDiagnosticVerdict: verdicts
        )
    }

    /// Store slots 2 and 4 — a live session on the store desktop.  Slot 2
    /// is the bare remote screen; slot 4 expands the accessory strip's
    /// function row over the same state.
    private static func storeSessionActiveSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: storeDesktop()
        )
    }

    /// Store slot 3 — the local-composition differentiator.  The draft
    /// text is seeded on the snapshot rather than typed by the UI test:
    /// simulator IME typing is not reliable enough to gate a release
    /// capture on, and what the slot has to show is the *editor holding
    /// finished Hangul before it crosses to the remote machine*.
    private static func storeSessionKoreanComposeSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(
                sessionID: session.id,
                text: "회의록 정리해서 커밋 메시지로 만들어줘"
            ),
            latestFramebuffer: storeDesktop()
        )
    }

    /// Store slot 5 — a diagnostics run that passed all the way to the
    /// first frame.  Every string here comes from the same safe-detail
    /// vocabulary the production catalog uses (constitution §IV): no
    /// raw error text, no host secrets.
    private static func storeDiagnosticsPassedSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 5),
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
                    status: .passed,
                    safeTitle: "Authenticated",
                    safeDetail: "The saved password was accepted.",
                    timestamp: fixedDate(offsetSeconds: 4)
                ),
                DiagnosticStageResult(
                    stage: .firstFrame,
                    status: .passed,
                    safeTitle: "First frame received",
                    safeDetail: "The remote screen is streaming.",
                    timestamp: fixedDate(offsetSeconds: 5)
                )
            ]
        )
        // The sheet only covers the lower part of the screen, so the card
        // behind it is in the capture too — give it a preview and a healthy
        // badge instead of the "No preview yet / Unknown" placeholder.
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run,
            profilePreviews: [
                profile.id: desktopPreview(
                    machineName: "STUDIO MAC",
                    status: "BUILD PASSED",
                    tint: (1.00, 1.00, 1.00)
                )
            ],
            profileReachability: [profile.id: .reachable],
            lastDiagnosticVerdict: [profile.id: .passed]
        )
    }

    /// Nearest-neighbour downscale of the shared synthetic desktop into
    /// a grid preview, so store cards show recognisable desktop
    /// structure (title bar, terminal window, sidebars) instead of an
    /// abstract gradient.  `tint` scales each channel so sibling cards
    /// differ; values are clamped to the byte range.
    private static func desktopPreview(
        machineName: String,
        status: String,
        tint: (red: Double, green: Double, blue: Double)
    ) -> ProfilePreviewThumbnail {
        let source = storeDesktopFramebuffer(machineName: machineName, status: status)
        let width = min(320, source.width / 2)
        let height = max(1, source.height * width / max(source.width, 1))

        var pixels: [RFBColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let sourceRow = min(source.height - 1, y * source.height / height)
            for x in 0..<width {
                let sourceColumn = min(source.width - 1, x * source.width / width)
                let pixel = source.pixels[sourceRow * source.width + sourceColumn]
                pixels.append(
                    RFBColor(
                        red: scaleChannel(pixel.red, by: tint.red),
                        green: scaleChannel(pixel.green, by: tint.green),
                        blue: scaleChannel(pixel.blue, by: tint.blue)
                    )
                )
            }
        }

        return ProfilePreviewThumbnail(
            width: width,
            height: height,
            sourceWidth: 1600,
            sourceHeight: 900,
            capturedAt: fixedDate(offsetSeconds: 7),
            pixels: pixels
        )
    }

    private static func scaleChannel(_ value: UInt8, by factor: Double) -> UInt8 {
        UInt8(min(255, max(0, (Double(value) * factor).rounded())))
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
    /// 16:9 / 16:10; before this fixture existed the container
    /// hardcoded 4:3 and double-letterboxed widescreen frames into a
    /// small box.  Keep the framebuffer synthetic and non-secret, but
    /// include representative window structure and readable terminal
    /// text so UX audit screenshots prove more than a flat rectangle.
    private static func sessionActiveWidescreenSnapshot(
        serverCursor: RFBServerCursor? = nil
    ) -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        let framebuffer = activeSessionDesktopFramebuffer()
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: framebuffer,
            latestServerCursor: serverCursor
        )
    }

    private static func sessionDegradedSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .degraded,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: activeSessionDesktopFramebuffer()
        )
    }

    private static func sessionActiveComposeConfirmationUnavailableSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        let framebuffer = activeSessionDesktopFramebuffer()
        let draft = ComposeDraft(sessionID: session.id, text: "")
        let attempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: session.id,
            path: .vncClipboardPaste,
            pasteCommand: .commandV,
            payloadEncoding: .ascii,
            startedAt: fixedDate(offsetSeconds: 6),
            finishedAt: fixedDate(offsetSeconds: 6),
            status: .unknown,
            clipboardSetStatus: .succeeded,
            pasteCommandStatus: .succeeded,
            safeMessage: "Remote app confirmation unavailable."
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: draft,
            latestInjectionAttempt: attempt,
            latestFramebuffer: framebuffer
        )
    }

    private static func sessionConnectingDelayedFirstFrameSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .connecting
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id)
        )
    }

    static func sampleWidescreenFramebuffer() -> RFBRawFramebuffer {
        return activeSessionDesktopFramebuffer()
    }

    /// The audit desktop: a 16:9 remote screen with representative window
    /// structure and readable terminal text, so a session capture proves
    /// more than a flat rectangle (spec 003 FR-001 — the container used to
    /// hardcode 4:3 and double-letterbox widescreen frames).
    ///
    /// Layout is deliberately frozen: several audit captures are graded
    /// against earlier ones. The store desktop below is a separate layout
    /// for that reason.
    private static func activeSessionDesktopFramebuffer() -> RFBRawFramebuffer {
        var canvas = FramebufferCanvas(width: 640, height: 360)
        canvas.paintDesktopBackdrop()

        canvas.fill(x: 0, y: 0, width: canvas.width, height: 28, color: chromeFill)
        canvas.fill(x: 0, y: 28, width: canvas.width, height: 2, color: chromeEdge)
        canvas.drawText("STUDIO MAC", x: 250, y: 8, scale: 2, color: chromeLabel)

        canvas.drawPanel(x: 54, y: 62, width: 138, height: 108, title: "FILES", titleX: 76, titleY: 84)
        canvas.fill(x: 76, y: 118, width: 92, height: 8, color: accentTeal)
        canvas.fill(x: 76, y: 138, width: 70, height: 8, color: RFBColor(red: 0x73, green: 0x90, blue: 0xA8))

        canvas.drawPanel(x: 454, y: 62, width: 132, height: 108, title: "WATCH", titleX: 484, titleY: 84)
        canvas.fill(x: 486, y: 120, width: 68, height: 10, color: accentTeal)
        canvas.fill(x: 486, y: 142, width: 48, height: 10, color: accentAmber)

        canvas.drawTerminalWindow(x: 200, y: 48, width: 244, height: 266, titleX: 278)
        for (index, line) in [
            "NARU REMOTE",
            "BUILD PASSED",
            "TAILNET READY",
            "NO SECRET DATA"
        ].enumerated() {
            canvas.drawCenteredText(
                line,
                centerX: 322,
                y: 92 + index * 48,
                scale: 3,
                color: terminalPalette[index]
            )
        }

        canvas.fill(x: 218, y: 288, width: 206, height: 8, color: chromeEdge)
        canvas.fill(x: 218, y: 288, width: 142, height: 8, color: accentTeal)
        canvas.drawText("CPU 18  NET 2", x: 236, y: 326, scale: 2, color: RFBColor(red: 0xA8, green: 0xB8, blue: 0xCA))

        return canvas.framebuffer()
    }

    /// The store desktop.  Same renderer as the audit desktop, different
    /// layout and different copy — an audit frame carries reminders aimed at
    /// this repository ("NO SECRET DATA"); a store frame has to read as
    /// somebody's actual machine.
    ///
    /// The layout is fractional because it has to survive the viewport's
    /// crop, and the crop differs per device.  The hero viewport is
    /// aspect-FILL by design (letterboxing a 16:9 desktop into a portrait
    /// phone would leave it unreadably small), so whatever the frame is
    /// wider/taller than the screen gets cut: a 6.9" phone in landscape is
    /// ~2.17:1 against 16:9 and loses ~9% off the top and bottom.  Laying
    /// the desktop out in fractions of the canvas means the tablet variant
    /// — a 4:3 frame for a 4:3 iPad screen, which fills with no crop at all
    /// — is a size argument rather than a second hand-tuned layout.
    ///
    /// The remaining crop is deliberate and it is *not* clipped content:
    /// only the empty menu-bar band leaves the frame.
    private static func storeDesktopFramebuffer(
        machineName: String = "STUDIO MAC",
        status: String = "BUILD PASSED",
        width: Int = 640,
        height: Int = 360
    ) -> RFBRawFramebuffer {
        var canvas = FramebufferCanvas(width: width, height: height)
        canvas.paintDesktopBackdrop()

        func across(_ fraction: Double) -> Int { Int((Double(width) * fraction).rounded()) }
        func down(_ fraction: Double) -> Int { Int((Double(height) * fraction).rounded()) }

        // Menu bar deep enough that its label clears the crop band.
        canvas.fill(x: 0, y: 0, width: width, height: down(0.189), color: chromeFill)
        canvas.fill(x: 0, y: down(0.189), width: width, height: 2, color: chromeEdge)
        canvas.drawCenteredText(
            machineName,
            centerX: width / 2,
            y: down(0.122),
            scale: 2,
            color: chromeLabel
        )

        let panelY = down(0.289)
        let panelWidth = across(0.219)
        let panelHeight = down(0.322)
        canvas.drawPanel(
            x: across(0.053),
            y: panelY,
            width: panelWidth,
            height: panelHeight,
            title: "FILES",
            titleX: across(0.088),
            titleY: down(0.350)
        )
        canvas.fill(x: across(0.088), y: down(0.450), width: across(0.150), height: 8, color: accentTeal)
        canvas.fill(
            x: across(0.088),
            y: down(0.506),
            width: across(0.113),
            height: 8,
            color: RFBColor(red: 0x73, green: 0x90, blue: 0xA8)
        )

        canvas.drawPanel(
            x: across(0.728),
            y: panelY,
            width: panelWidth,
            height: panelHeight,
            title: "WATCH",
            titleX: across(0.766),
            titleY: down(0.350)
        )
        canvas.fill(x: across(0.766), y: down(0.450), width: across(0.109), height: 10, color: accentTeal)
        canvas.fill(x: across(0.766), y: down(0.511), width: across(0.078), height: 10, color: accentAmber)

        let terminalX = across(0.297)
        canvas.drawTerminalWindow(
            x: terminalX,
            y: down(0.250),
            width: across(0.406),
            height: down(0.600),
            titleX: terminalX + across(0.128)
        )
        for (index, line) in ["NARU REMOTE", status, "TAILNET READY", "AGENT ONLINE"].enumerated() {
            canvas.drawCenteredText(
                line,
                centerX: width / 2,
                y: down(0.361) + index * down(0.117),
                scale: 3,
                color: terminalPalette[index]
            )
        }

        canvas.fill(x: across(0.328), y: down(0.811), width: across(0.344), height: 8, color: chromeEdge)
        canvas.fill(x: across(0.328), y: down(0.811), width: across(0.238), height: 8, color: accentTeal)

        return canvas.framebuffer()
    }

    /// The store desktop at the aspect the capture device wants.
    ///
    /// `NARU_TEST_FIXTURE_DESKTOP=tablet` asks for 4:3, because a 13" iPad's
    /// own screen is 4:3 and the aspect-fill viewport crops a quarter off a
    /// 16:9 frame there; the phone keeps 16:9, which is what a real desktop
    /// usually is.  A launch variable rather than a second fixture token:
    /// the state under capture is identical, only the remote screen's shape
    /// differs.
    private static func storeDesktop() -> RFBRawFramebuffer {
        let wantsTablet = ProcessInfo.processInfo
            .environment["NARU_TEST_FIXTURE_DESKTOP"]?
            .trimmedNonEmpty?
            .lowercased() == "tablet"
        return storeDesktopFramebuffer(
            width: 640,
            height: wantsTablet ? 480 : 360
        )
    }

    private static let chromeFill = RFBColor(red: 0x0B, green: 0x12, blue: 0x1D)
    private static let chromeEdge = RFBColor(red: 0x2C, green: 0x58, blue: 0x74)
    private static let chromeLabel = RFBColor(red: 0xB8, green: 0xC7, blue: 0xD7)
    private static let accentTeal = RFBColor(red: 0x38, green: 0xB6, blue: 0xA5)
    private static let accentAmber = RFBColor(red: 0xF5, green: 0xB9, blue: 0x42)
    private static let terminalPalette = [
        RFBColor(red: 0xE6, green: 0xF0, blue: 0xFA),
        RFBColor(red: 0x69, green: 0xE0, blue: 0xB0),
        RFBColor(red: 0x8D, green: 0xD5, blue: 0xFF),
        RFBColor(red: 0xF2, green: 0xD0, blue: 0x7A)
    ]

    /// Minimal software rasteriser shared by the fixture desktops.  It
    /// exists so a second desktop layout costs a layout function instead
    /// of a second copy of the drawing primitives — the first store
    /// capture round needed one and the primitives were nested locals.
    private struct FramebufferCanvas {
        let width: Int
        let height: Int
        private var pixels: [RFBColor]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            self.pixels = Array(
                repeating: RFBColor(red: 0x11, green: 0x1B, blue: 0x26),
                count: width * height
            )
        }

        func framebuffer() -> RFBRawFramebuffer {
            RFBRawFramebuffer(width: width, height: height, pixels: pixels)
        }

        mutating func fill(x: Int, y: Int, width rectWidth: Int, height rectHeight: Int, color: RFBColor) {
            let minX = max(x, 0)
            let minY = max(y, 0)
            let maxX = min(x + rectWidth, width)
            let maxY = min(y + rectHeight, height)
            guard minX < maxX, minY < maxY else {
                return
            }
            for row in minY..<maxY {
                let base = row * width
                for column in minX..<maxX {
                    pixels[base + column] = color
                }
            }
        }

        mutating func stroke(x: Int, y: Int, width rectWidth: Int, height rectHeight: Int, color: RFBColor) {
            fill(x: x, y: y, width: rectWidth, height: 2, color: color)
            fill(x: x, y: y + rectHeight - 2, width: rectWidth, height: 2, color: color)
            fill(x: x, y: y, width: 2, height: rectHeight, color: color)
            fill(x: x + rectWidth - 2, y: y, width: 2, height: rectHeight, color: color)
        }

        /// Glyph coverage is A–Z, 0–9 and space; anything else renders as
        /// "?", so callers keep fixture copy inside that alphabet.
        private mutating func drawGlyphs(_ text: String, x: Int, y: Int, scale: Int, color: RFBColor) {
            var cursorX = x
            let advance = 6 * scale
            for character in text {
                let glyph = UXAuditFixtures.framebufferGlyphs[character] ?? UXAuditFixtures.framebufferGlyphs["?"]!
                for (rowIndex, row) in glyph.enumerated() {
                    for (columnIndex, bit) in row.enumerated() where bit == "1" {
                        fill(
                            x: cursorX + columnIndex * scale,
                            y: y + rowIndex * scale,
                            width: scale,
                            height: scale,
                            color: color
                        )
                    }
                }
                cursorX += advance
            }
        }

        mutating func drawText(_ text: String, x: Int, y: Int, scale: Int, color: RFBColor) {
            drawGlyphs(
                text,
                x: x + max(scale / 2, 1),
                y: y + max(scale / 2, 1),
                scale: scale,
                color: RFBColor(red: 0x03, green: 0x07, blue: 0x10)
            )
            drawGlyphs(text, x: x, y: y, scale: scale, color: color)
        }

        mutating func drawCenteredText(
            _ text: String,
            centerX: Int,
            y: Int,
            scale: Int,
            color: RFBColor
        ) {
            let advance = 6 * scale
            drawText(text, x: centerX - (text.count * advance) / 2, y: y, scale: scale, color: color)
        }

        mutating func paintDesktopBackdrop() {
            for y in 0..<height {
                let lift = min(34, y * 34 / max(height - 1, 1))
                fill(
                    x: 0,
                    y: y,
                    width: width,
                    height: 1,
                    color: RFBColor(
                        red: 0x10,
                        green: UInt8(0x1A + lift / 2),
                        blue: UInt8(0x27 + lift)
                    )
                )
            }
        }

        mutating func drawPanel(
            x: Int,
            y: Int,
            width panelWidth: Int,
            height panelHeight: Int,
            title: String,
            titleX: Int,
            titleY: Int
        ) {
            fill(
                x: x,
                y: y,
                width: panelWidth,
                height: panelHeight,
                color: RFBColor(red: 0x18, green: 0x25, blue: 0x34)
            )
            stroke(x: x, y: y, width: panelWidth, height: panelHeight, color: UXAuditFixtures.chromeEdge)
            drawText(
                title,
                x: titleX,
                y: titleY,
                scale: 2,
                color: RFBColor(red: 0x8D, green: 0xD5, blue: 0xFF)
            )
        }

        mutating func drawTerminalWindow(
            x: Int,
            y: Int,
            width windowWidth: Int,
            height windowHeight: Int,
            titleX: Int
        ) {
            fill(
                x: x,
                y: y,
                width: windowWidth,
                height: windowHeight,
                color: RFBColor(red: 0x07, green: 0x0D, blue: 0x16)
            )
            stroke(
                x: x,
                y: y,
                width: windowWidth,
                height: windowHeight,
                color: RFBColor(red: 0x47, green: 0x75, blue: 0x8F)
            )
            fill(
                x: x + 2,
                y: y + 2,
                width: windowWidth - 4,
                height: 26,
                color: RFBColor(red: 0x15, green: 0x26, blue: 0x35)
            )
            fill(x: x + 16, y: y + 12, width: 8, height: 8, color: RFBColor(red: 0xFF, green: 0x6B, blue: 0x6B))
            fill(x: x + 32, y: y + 12, width: 8, height: 8, color: UXAuditFixtures.accentAmber)
            fill(x: x + 48, y: y + 12, width: 8, height: 8, color: UXAuditFixtures.accentTeal)
            drawText(
                "TERMINAL",
                x: titleX,
                y: y + 8,
                scale: 2,
                color: RFBColor(red: 0xC7, green: 0xD7, blue: 0xEA)
            )
        }
    }

    private static let framebufferGlyphs: [Character: [String]] = [
        " ": [
            "00000",
            "00000",
            "00000",
            "00000",
            "00000",
            "00000",
            "00000"
        ],
        "?": [
            "01110",
            "10001",
            "00001",
            "00010",
            "00100",
            "00000",
            "00100"
        ],
        "0": [
            "01110",
            "10001",
            "10011",
            "10101",
            "11001",
            "10001",
            "01110"
        ],
        "1": [
            "00100",
            "01100",
            "00100",
            "00100",
            "00100",
            "00100",
            "01110"
        ],
        "2": [
            "01110",
            "10001",
            "00001",
            "00010",
            "00100",
            "01000",
            "11111"
        ],
        "3": [
            "11110",
            "00001",
            "00001",
            "01110",
            "00001",
            "00001",
            "11110"
        ],
        "4": [
            "00010",
            "00110",
            "01010",
            "10010",
            "11111",
            "00010",
            "00010"
        ],
        "5": [
            "11111",
            "10000",
            "10000",
            "11110",
            "00001",
            "00001",
            "11110"
        ],
        "6": [
            "01110",
            "10000",
            "10000",
            "11110",
            "10001",
            "10001",
            "01110"
        ],
        "7": [
            "11111",
            "00001",
            "00010",
            "00100",
            "01000",
            "01000",
            "01000"
        ],
        "8": [
            "01110",
            "10001",
            "10001",
            "01110",
            "10001",
            "10001",
            "01110"
        ],
        "9": [
            "01110",
            "10001",
            "10001",
            "01111",
            "00001",
            "00001",
            "01110"
        ],
        "A": [
            "01110",
            "10001",
            "10001",
            "11111",
            "10001",
            "10001",
            "10001"
        ],
        "B": [
            "11110",
            "10001",
            "10001",
            "11110",
            "10001",
            "10001",
            "11110"
        ],
        "C": [
            "01111",
            "10000",
            "10000",
            "10000",
            "10000",
            "10000",
            "01111"
        ],
        "D": [
            "11110",
            "10001",
            "10001",
            "10001",
            "10001",
            "10001",
            "11110"
        ],
        "E": [
            "11111",
            "10000",
            "10000",
            "11110",
            "10000",
            "10000",
            "11111"
        ],
        "F": [
            "11111",
            "10000",
            "10000",
            "11110",
            "10000",
            "10000",
            "10000"
        ],
        "G": [
            "01111",
            "10000",
            "10000",
            "10011",
            "10001",
            "10001",
            "01111"
        ],
        "H": [
            "10001",
            "10001",
            "10001",
            "11111",
            "10001",
            "10001",
            "10001"
        ],
        "I": [
            "11111",
            "00100",
            "00100",
            "00100",
            "00100",
            "00100",
            "11111"
        ],
        "J": [
            "00111",
            "00010",
            "00010",
            "00010",
            "10010",
            "10010",
            "01100"
        ],
        "K": [
            "10001",
            "10010",
            "10100",
            "11000",
            "10100",
            "10010",
            "10001"
        ],
        "L": [
            "10000",
            "10000",
            "10000",
            "10000",
            "10000",
            "10000",
            "11111"
        ],
        "M": [
            "10001",
            "11011",
            "10101",
            "10101",
            "10001",
            "10001",
            "10001"
        ],
        "N": [
            "10001",
            "11001",
            "10101",
            "10011",
            "10001",
            "10001",
            "10001"
        ],
        "O": [
            "01110",
            "10001",
            "10001",
            "10001",
            "10001",
            "10001",
            "01110"
        ],
        "P": [
            "11110",
            "10001",
            "10001",
            "11110",
            "10000",
            "10000",
            "10000"
        ],
        "Q": [
            "01110",
            "10001",
            "10001",
            "10001",
            "10101",
            "10010",
            "01101"
        ],
        "R": [
            "11110",
            "10001",
            "10001",
            "11110",
            "10100",
            "10010",
            "10001"
        ],
        "S": [
            "01111",
            "10000",
            "10000",
            "01110",
            "00001",
            "00001",
            "11110"
        ],
        "T": [
            "11111",
            "00100",
            "00100",
            "00100",
            "00100",
            "00100",
            "00100"
        ],
        "U": [
            "10001",
            "10001",
            "10001",
            "10001",
            "10001",
            "10001",
            "01110"
        ],
        "V": [
            "10001",
            "10001",
            "10001",
            "10001",
            "10001",
            "01010",
            "00100"
        ],
        "W": [
            "10001",
            "10001",
            "10001",
            "10101",
            "10101",
            "10101",
            "01010"
        ],
        "X": [
            "10001",
            "10001",
            "01010",
            "00100",
            "01010",
            "10001",
            "10001"
        ],
        "Y": [
            "10001",
            "10001",
            "01010",
            "00100",
            "00100",
            "00100",
            "00100"
        ],
        "Z": [
            "11111",
            "00001",
            "00010",
            "00100",
            "01000",
            "10000",
            "11111"
        ]
    ]

    private static func serverCursorArrow() -> RFBServerCursor {
        let width = 24
        let height = 32
        let transparent = RFBColor(red: 0, green: 0, blue: 0, alpha: 0)
        let white = RFBColor(red: 255, green: 255, blue: 255)
        let black = RFBColor(red: 0, green: 0, blue: 0)
        var pixels = Array(repeating: transparent, count: width * height)

        func paint(_ x: Int, _ y: Int, _ color: RFBColor) {
            guard x >= 0, x < width, y >= 0, y < height else {
                return
            }
            pixels[y * width + x] = color
        }

        for y in 0..<22 {
            for x in 0...min(y, 13) {
                let border = x == 0 || x == min(y, 13) || y == 21
                paint(x, y, border ? black : white)
            }
        }
        for y in 17..<31 {
            for x in 8..<14 {
                let border = x == 8 || x == 13 || y == 30
                paint(x, y, border ? black : white)
            }
        }
        for y in 24..<31 {
            for x in 14..<21 {
                let border = y == 24 || y == 30 || x == 20
                paint(x, y, border ? black : white)
            }
        }

        return RFBServerCursor(
            width: width,
            height: height,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: pixels
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

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Dictionary where Key == String, Value == String {
    func isTruthy(_ key: String) -> Bool {
        guard let raw = self[key]?.trimmedNonEmpty?.lowercased() else {
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes"
    }
}
#endif
