import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import NaruHelperKit
import NaruRemoteCore
import SwiftUI

/// Owns everything the menu and the pairing window observe (spec 041
/// T-B2). Every decision lives in `NaruHelperKit` — listener lifecycle,
/// pairing/rotation/revoke semantics, login-item transitions, diagnostics
/// text — this type wires those pieces to published state and drives the
/// non-prompting permission probes on a 2 s poll that only runs while a
/// surface is watching (spec 041 T-B2).
@MainActor
final class HelperAppModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var pairingStatus: NaruHelperPairingStatus = .notPaired
    @Published private(set) var accessibility: NaruHelperPermissionStatus = .missing
    @Published private(set) var screenRecording: NaruHelperPermissionStatus = .missing
    @Published private(set) var textListenerState: NaruHelperListenerState = .stopped
    @Published private(set) var videoListenerState: NaruHelperListenerState = .stopped
    @Published private(set) var loginItemState: NaruHelperLoginItemState = .off
    @Published private(set) var hostInfo: NaruHelperPairingHostInfo?
    /// True while the tailnet address / MagicDNS name is being resolved
    /// off the main actor; the window shows progress instead of a blank.
    @Published private(set) var isResolvingHostInfo = false
    private var hostInfoRequestGeneration = 0
    @Published private(set) var pairingSession: NaruHelperPairingSession?
    /// Memory only (spec 041 FR-004 / SP-003): the optional VNC password
    /// exists for the one QR it was entered for and is never persisted.
    @Published var vncPassword = ""

    // MARK: Wiring

    private let store: NaruHelperPairingStateStore
    private let loginItemController: any NaruHelperLoginItemControlling
    private var runtime: NaruHelperListenerRuntime?
    private var permissionTimer: Timer?
    private var lastMenuOpenedAt: Date?
    private var pairingWindowVisible = false
    /// Round A note: the runtime's authorized hook fires on EVERY accepted
    /// request, not once — `connected` is latched on the first fire.
    private var connectedLatched = false
    private var didBecomeActiveObserver: (any NSObjectProtocol)?

    #if DEBUG
    private let uiFixtures: HelperUITestFixtures?
    /// Rendered once at init: `displayedQRImage` is read on every body
    /// evaluation, and generating a QR (CIContext + filter) per read made
    /// the fixture window appear to hang (lead review 2026-09-06).
    private let uiFixtureQRImage: CGImage?
    /// Read by `HelperUITestSurface` to decide which DEBUG fixture windows
    /// to present. `nil` in every normal launch.
    var uiTestFixtures: HelperUITestFixtures? { uiFixtures }
    #endif

    init(loginItemController: any NaruHelperLoginItemControlling = SystemLoginItem.shared) {
        self.loginItemController = loginItemController
        #if DEBUG
        let fixtures = HelperUITestFixtures.parse(ProcessInfo.processInfo.arguments)
        self.uiFixtures = fixtures
        self.uiFixtureQRImage = fixtures?.offer.flatMap { NaruHelperPairingSession.makeQRImage(message: $0) }
        // UI tests must never rotate the real `~/.naru` state: with the
        // fixture flag set, the whole process points its store at a temp
        // directory supplied by `--ui-test-state-dir`.
        if let stateDirectory = fixtures?.stateDirectory {
            self.store = NaruHelperPairingStateStore(
                fileURL: URL(fileURLWithPath: stateDirectory, isDirectory: true)
                    .appendingPathComponent("helper-pairing-state.json"))
        } else {
            self.store = NaruHelperPairingStateStore()
        }
        #else
        self.store = NaruHelperPairingStateStore()
        #endif
        self.didBecomeActiveObserver = nil

        observeApplicationActive()
        refreshPermissions()
        refreshPairingStatus()
        #if DEBUG
        if uiFixtures != nil {
            // Fixture launches render state; they do not bind ports. Binding
            // 5974/5975 in a UI test would trigger macOS's Local Network
            // prompt over the capture (measured 2026-09-06: every first
            // capture was occluded by it) and could collide with a real
            // helper on the same Mac.
            textListenerState = .listening(port: UInt16(naruHelperTextBridgeDefaultPort))
            videoListenerState = .listening(port: UInt16(naruHelperVideoStreamDefaultPort))
        } else {
            startRuntime()
        }
        #else
        startRuntime()
        #endif
        refreshLoginItemState()
    }

    // No deinit teardown: the model is process-lifetime (owned by the
    // app delegate for the app's whole run), and a nonisolated deinit
    // cannot touch this MainActor state under Swift 6.

    // MARK: Aggregated status

    /// The fixed-catalog aggregate behind **Copy Diagnostics** (spec 041
    /// FR-012) — recomputed from the published components, so menu,
    /// window, and pasteboard can never disagree.
    var status: NaruHelperAppStatus {
        NaruHelperAppStatus(
            accessibility: accessibility,
            screenRecording: screenRecording,
            textListener: textListenerState,
            videoListener: videoListenerState,
            pairing: pairingStatus,
            loginItem: loginItemState,
            version: versionText)
    }

    /// `"<marketing> (<build>)"` — one owner for the menu's version row
    /// and the diagnostics line so they cannot drift apart.
    var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    // MARK: Runtime

    private func startRuntime() {
        let runtime: NaruHelperListenerRuntime
        do {
            runtime = try NaruHelperListenerRuntime(
                store: store,
                textPort: UInt16(naruHelperTextBridgeDefaultPort),
                videoPort: UInt16(naruHelperVideoStreamDefaultPort),
                onAuthorizedRequest: { [weak self] in
                    Task { @MainActor in self?.handleAuthorizedRequest() }
                },
                capabilityProvider: {
                    NaruHelperTextBridgeLive.capabilityResponse()
                },
                insertHandler: { request in
                    NaruHelperTextBridgeLive.insert(request: request)
                })
        } catch {
            textListenerState = .failed
            videoListenerState = .failed
            return
        }
        // Listener states arrive on the listeners' dispatch queues (Kit
        // contract) — hop to the main actor before touching published
        // state.
        runtime.onStateChange = { [weak self] kind, state in
            Task { @MainActor in self?.applyListenerState(kind, state) }
        }
        runtime.start()
        self.runtime = runtime
    }

    private func applyListenerState(_ kind: NaruHelperListenerKind, _ state: NaruHelperListenerState) {
        switch kind {
        case .text: textListenerState = state
        case .video: videoListenerState = state
        }
    }

    // MARK: Pairing

    private func handleAuthorizedRequest() {
        guard !connectedLatched else { return }
        connectedLatched = true
        // The QR is credential material (spec 041 FR-003): the first
        // accepted handshake retires it and clears the optional VNC
        // password from memory.
        endPairingSession()
        vncPassword = ""
        refreshPairingStatus()
    }

    /// `notPaired` ⇔ the store answers no current secret (file absent:
    /// never paired, or revoked); `connected` is the latched authorized
    /// hook promoting `paired`. Reads the store per call — never a cached
    /// snapshot — so revoke and rotation elsewhere are honored.
    func refreshPairingStatus() {
        #if DEBUG
        if let fixturePairing = uiFixtures?.pairingStatus {
            pairingStatus = fixturePairing
            return
        }
        #endif
        guard store.currentSecret() != nil else {
            connectedLatched = false
            pairingStatus = .notPaired
            return
        }
        pairingStatus = connectedLatched ? .connected : .paired
    }

    /// One **Pair with iPhone…** / **Regenerate QR** / **Retry**: re-reads
    /// host info, retires any prior session, and (when a tailnet address
    /// exists) begins a fresh session — which rotates the token (spec 041
    /// FR-003: opening the window mints; a second mint supersedes).
    func beginPairingSession() {
        #if DEBUG
        // Fixture display only: a UI test with an injected offer renders
        // the fixture QR, never mints a token against any store, and never
        // touches the resolver.
        if uiFixtures?.offer != nil {
            hostInfo = NaruHelperPairingHostInfo(label: "Fixture Mac", addresses: ["100.64.0.10"])
            isResolvingHostInfo = false
            return
        }
        #endif
        endPairingSession()
        // `NaruHelperPairingHostInfo.current()` reverse-resolves the tailnet
        // address with a blocking `getnameinfo`; sampled on the main thread
        // 2026-09-06 it held the pairing window blank for the resolver's
        // whole timeout (tens of seconds). Resolve off the main actor and
        // let a stale answer lose to a newer request.
        hostInfoRequestGeneration += 1
        let generation = hostInfoRequestGeneration
        isResolvingHostInfo = true
        Task { [weak self] in
            // The resolver runs on a background executor; only the result
            // crosses back to the main actor.
            let resolved = await Task.detached(priority: .userInitiated) {
                NaruHelperPairingHostInfo.current()
            }.value
            self?.completeHostInfoResolution(resolved, generation: generation)
        }
    }

    private func completeHostInfoResolution(_ resolved: NaruHelperPairingHostInfo?, generation: Int) {
        guard generation == hostInfoRequestGeneration else { return }
        isResolvingHostInfo = false
        hostInfo = resolved
        guard pairingWindowVisible, let hostInfo else { return }
        do {
            pairingSession = try NaruHelperPairingSession.begin(
                store: store,
                hostInfo: hostInfo,
                vncPassword: vncPassword.isEmpty ? nil : vncPassword)
        } catch {
            pairingSession = nil
        }
        // A rotation supersedes whichever phone connected before it
        // (spec 040 FR-002), so the "connected" latch cannot survive it —
        // otherwise reopening the window would mint a new token while the
        // view still reads "Paired — iPhone connected" over a dead one
        // (lead review 2026-09-06).
        connectedLatched = false
        refreshPairingStatus()
    }

    func endPairingSession() {
        pairingSession?.end()
        pairingSession = nil
    }

    func revokePairing() {
        // The Kit's per-request providers read the store per handshake,
        // so removing the file refuses every subsequent handshake with
        // the fixed `revoked` code (spec 041 FR-007).
        try? store.revoke()
        connectedLatched = false
        endPairingSession()
        vncPassword = ""
        refreshPairingStatus()
    }

    /// Confirmation lives here rather than in a SwiftUI `.alert` because
    /// menu-style `MenuBarExtra` content is dismissed the instant the
    /// button fires — a presentation attached to it goes away with the
    /// menu. A modal `NSAlert` survives the menu closing.
    func confirmRevokePairing() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Revoke pairing?"
        alert.informativeText = "Every phone that holds the current code will need to scan again."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        revokePairing()
    }

    // MARK: Pairing display

    enum PairingDisplay {
        /// Resolver still running (see ``beginPairingSession()``).
        case resolving
        /// No CGNAT address — Naru refuses to pair over public internet
        /// (constitution §II), stated plainly with a retry.
        case noTailnetAddress
        case offer
    }

    var pairingDisplay: PairingDisplay {
        #if DEBUG
        if uiFixtures?.offer != nil { return .offer }
        #endif
        if isResolvingHostInfo { return .resolving }
        return hostInfo == nil ? .noTailnetAddress : .offer
    }

    var displayedOfferURL: String? {
        #if DEBUG
        if let offer = uiFixtures?.offer { return offer }
        #endif
        return pairingSession?.offerURL
    }

    var displayedQRImage: CGImage? {
        #if DEBUG
        if uiFixtures?.offer != nil {
            return uiFixtureQRImage
        }
        #endif
        return pairingSession?.qrImage
    }

    // MARK: Window/menu lifecycle

    func pairingWindowAppeared() {
        pairingWindowVisible = true
        beginPairingSession()
        refreshPermissions()
        ensurePermissionTimer()
    }

    func pairingWindowDisappeared() {
        pairingWindowVisible = false
        // Closing the window retires the QR and clears the password
        // (spec 041 FR-003 / SP-003); the token itself stays valid until
        // the next rotation — a closed window does not revoke.
        endPairingSession()
        vncPassword = ""
        stopPermissionTimerIfNeeded()
    }

    func noteMenuOpened() {
        lastMenuOpenedAt = Date()
        refreshPermissions()
        refreshPairingStatus()
        ensurePermissionTimer()
    }

    private func ensurePermissionTimer() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
                self?.stopPermissionTimerIfNeeded()
            }
        }
    }

    /// The poll lives only while the pairing window is open or the menu
    /// was opened in the last 10 s (spec 041 T-B2) — an idle menu bar app
    /// runs no timers.
    private func stopPermissionTimerIfNeeded() {
        guard !pairingWindowVisible else { return }
        if let lastMenuOpenedAt, Date().timeIntervalSince(lastMenuOpenedAt) < 10 { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: Permissions

    /// Non-prompting probes only (spec 041 R4): the prompting/requesting
    /// calls are reachable solely through the System Settings buttons,
    /// never from this poll.
    func refreshPermissions() {
        #if DEBUG
        if let granted = uiFixtures?.permissionsGranted {
            accessibility = granted ? .granted : .missing
            screenRecording = granted ? .granted : .missing
            return
        }
        #endif
        accessibility = AXIsProcessTrusted() ? .granted : .missing
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .missing
    }

    enum PermissionPane {
        case accessibility
        case screenRecording

        /// The one-click route of spec 041 FR-005.
        var settingsURL: URL {
            switch self {
            case .accessibility:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .screenRecording:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            }
        }
    }

    /// User-initiated (a button press), so this is the one place the
    /// *prompting* request is allowed (spec 041 R4). The request matters
    /// beyond the dialog it may show: macOS only lists an app under
    /// Privacy & Security → Screen Recording / Accessibility **after that
    /// app has asked once**. Without it the Settings pane opens to a list
    /// the helper is absent from, and the user has no toggle to flip
    /// (observed 2026-09-06 on the Debug build). The request is the same
    /// Kit path the CLI's `--request-permissions` uses; the pane is opened
    /// afterwards regardless of the answer, so a denial still lands the
    /// user on the toggle. The poll (``refreshPermissions()``) stays
    /// non-prompting.
    func openPermissionSettings(_ pane: PermissionPane) {
        switch pane {
        case .accessibility:
            _ = NaruHelperTextPermissionRequester.live().request()
        case .screenRecording:
            _ = NaruHelperVideoScreenRecordingPermissionRequester.live().request()
        }
        refreshPermissions()
        NSWorkspace.shared.open(pane.settingsURL)
    }

    // MARK: Login item

    func setLoginItemEnabled(_ enabled: Bool) {
        // The pure Kit transition reports the system's answer — the
        // toggle never asserts success from its own request.
        loginItemState = NaruHelperLoginItemToggle(desiredEnabled: enabled)
            .apply(controller: loginItemController)
        // `.requiresApproval` is the system waiting on a user decision:
        // route there once, never retry in a loop (Kit contract).
        if enabled, loginItemState == .requiresApproval {
            SystemLoginItem.openSystemSettings()
        }
    }

    private func refreshLoginItemState() {
        loginItemState = loginItemController.status()
    }

    // MARK: Pasteboard

    func copyOfferCode() {
        guard let offer = displayedOfferURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(offer, forType: .string)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.diagnosticsText(), forType: .string)
    }

    // MARK: Observers

    private func observeApplicationActive() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }
}

#if DEBUG
/// Fixture launch arguments (spec 041 T-B5). Honored only when BOTH
/// guards hold: the code exists in a DEBUG build, and `--ui-test` is
/// among the process arguments. A normal launch — or any Release build —
/// parses nothing, and every fixture below affects display state or the
/// temp state directory only.
struct HelperUITestFixtures: Sendable {
    let offer: String?
    let stateDirectory: String?
    let pairingStatus: NaruHelperPairingStatus?
    let permissionsGranted: Bool?
    let openPairing: Bool
    let openMenuPreview: Bool

    static func parse(_ arguments: [String]) -> HelperUITestFixtures? {
        guard arguments.contains(uiTestFlag) else { return nil }
        return HelperUITestFixtures(
            offer: value(of: "--ui-test-offer", in: arguments),
            stateDirectory: value(of: "--ui-test-state-dir", in: arguments),
            pairingStatus: value(of: "--ui-test-state", in: arguments)
                .flatMap(Self.pairingStatus(from:)),
            permissionsGranted: value(of: "--ui-test-permissions", in: arguments)
                .flatMap(Self.boolean(from:)),
            openPairing: arguments.contains("--ui-test-open-pairing"),
            openMenuPreview: arguments.contains("--ui-test-open-menu-preview"))
    }

    private static let uiTestFlag = "--ui-test"

    private static func value(of name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        return arguments[arguments.index(after: index)]
    }

    private static func pairingStatus(from raw: String) -> NaruHelperPairingStatus? {
        switch raw {
        case "notPaired": .notPaired
        case "paired": .paired
        case "connected": .connected
        default: nil
        }
    }

    private static func boolean(from raw: String) -> Bool? {
        switch raw {
        case "granted": true
        case "missing": false
        default: nil
        }
    }
}

#endif
