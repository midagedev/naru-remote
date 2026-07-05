import NaruRemoteCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What the onboarding hands back to the profile editor on finish so
/// the editor can stage the secret into its existing Keychain save
/// path (constitution §IV — the secret rides `ProfileEditorCredentialUpdate`,
/// never `ConnectionProfile`).  The raw secret is transient: it lives in
/// the view's `@State` and this result value only until the editor
/// stores it in its own `@State` for the next Save.
public struct HelperOnboardingResult: Equatable, Sendable {
    public var secret: String
    public var fingerprint: String
    public var capabilities: HelperOnboardingCapabilities

    public init(secret: String, fingerprint: String, capabilities: HelperOnboardingCapabilities) {
        self.secret = secret
        self.fingerprint = fingerprint
        self.capabilities = capabilities
    }
}

/// Guided, phone-first sheet that gets Naru Helper running on the user's
/// Mac and paired with a profile without reading repo docs (spec 010).
/// Pure logic (step machine, secret, fingerprint, snippet) lives in
/// `NaruRemoteCore.HelperOnboarding`; this view is presentation + the
/// two explicit copy actions + the reachability verify hookup.
public struct HelperOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private let host: String
    private let port: Int
    /// Reachability runner reused from the profile editor's existing
    /// `onTest` (`runProfileEditorReachabilityTest`).  Optional so the
    /// verify step degrades to guidance when unavailable.
    private let onTestReachability: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)?
    /// Future in-flow helper-handshake test (spec 010 FR-013 Named API
    /// Gap).  Absent today because the shell passes only closures; when
    /// wired it returns the profile's helper availability.
    private let onTestHelper: (@MainActor () async -> HelperTextBridgeAvailability)?
    private let onApply: (HelperOnboardingResult) -> Void

    @State private var state = HelperOnboardingState()
    /// The raw generated secret — transient, view-local, cleared on
    /// dismiss.  Never stored in `HelperOnboardingState` (SP-002).
    @State private var secret: String = ""
    @State private var reachabilityMessage: String?
    @State private var isTesting = false
    @State private var didCopySecret = false
    @State private var didCopyCommands = false
    @State private var didApply = false

    public init(
        host: String,
        port: Int,
        existingFingerprint: String? = nil,
        capabilities: HelperOnboardingCapabilities = .both,
        onTestReachability: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)? = nil,
        onTestHelper: (@MainActor () async -> HelperTextBridgeAvailability)? = nil,
        onApply: @escaping (HelperOnboardingResult) -> Void
    ) {
        self.host = host
        self.port = port
        self.onTestReachability = onTestReachability
        self.onTestHelper = onTestHelper
        self.onApply = onApply
        _state = State(initialValue: HelperOnboardingState(capabilities: capabilities))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                Divider()
                ScrollView {
                    stepContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                actionBar
            }
            .navigationTitle(state.step.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("naru.helper.onboarding.cancel")
                }
            }
        }
        .accessibilityIdentifier("naru.helper.onboarding")
    }

    // MARK: - Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(state.step.displayIndex) of \(HelperOnboardingStep.stepCount)")
                .font(.caption)
                .foregroundStyle(NaruColors.mutedInk)
            ProgressView(
                value: Double(state.step.displayIndex),
                total: Double(HelperOnboardingStep.stepCount)
            )
            .tint(NaruColors.signalBlue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch state.step {
        case .intro: introStep
        case .configure: configureStep
        case .permissions: permissionsStep
        case .verify: verifyStep
        case .done: doneStep
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Naru Helper is optional")
                .font(.title3.weight(.semibold))
            Text("Basic viewing and text already work without it. The helper on your Mac unlocks the fast paths:")
                .foregroundStyle(NaruColors.mutedInk)
            benefit(icon: "bolt.fill", title: "Fast video",
                    detail: "Low-latency screen streaming, sharper than the VNC framebuffer.")
            benefit(icon: "character.cursor.ibeam", title: "Confirmed Korean & CJK text",
                    detail: "Composed text is inserted natively on the Mac with delivery you can see.")
            benefit(icon: "keyboard", title: "Live type-through quality",
                    detail: "Typing flows to the Mac as it commits, without a per-sentence wait.")
            Text("You will generate a pairing secret here, run a few commands on the Mac, and grant two macOS permissions. It takes a couple of minutes.")
                .font(.callout)
                .foregroundStyle(NaruColors.mutedInk)
                .padding(.top, 4)
        }
    }

    private var configureStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair this Mac")
                .font(.title3.weight(.semibold))
            Text("Naru generated a private pairing secret on this device. Copy it to your Mac, then copy the commands below.")
                .foregroundStyle(NaruColors.mutedInk)

            // Fingerprint (non-secret) — safe to display.
            if let fingerprint = state.fingerprint {
                labeledMono(title: "Profile fingerprint (not secret)", value: fingerprint)
            }

            // Secret — sensitive, behind an explicit copy action.
            VStack(alignment: .leading, spacing: 8) {
                Label("Pairing secret", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NaruColors.coral)
                Text("Sensitive — copy it straight to your Mac and don't paste it anywhere public. Clear your clipboard afterward.")
                    .font(.caption)
                    .foregroundStyle(NaruColors.mutedInk)
                HStack {
                    Button {
                        copy(secret)
                        didCopySecret = true
                    } label: {
                        Label(didCopySecret ? "Secret copied" : "Copy secret", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("naru.helper.onboarding.copySecret")

                    Button {
                        regenerateSecret()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("naru.helper.onboarding.regenerate")
                }
            }
            .padding(12)
            .background(NaruColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))

            // Mac snippet — contains no secret (env indirection).
            VStack(alignment: .leading, spacing: 8) {
                Text("Run on your Mac")
                    .font(.subheadline.weight(.semibold))
                Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(NaruColors.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(NaruColors.hairline)
                    )
                Button {
                    copy(snippet)
                    didCopyCommands = true
                } label: {
                    Label(didCopyCommands ? "Commands copied" : "Copy commands", systemImage: "terminal")
                }
                .accessibilityIdentifier("naru.helper.onboarding.copyCommands")
                Text("The commands reference your secret through an environment variable — the copied text contains no secret.")
                    .font(.caption2)
                    .foregroundStyle(NaruColors.mutedInk)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant two macOS permissions")
                .font(.title3.weight(.semibold))
            Text("macOS shows these prompts on the Mac, not on your phone. Approve them there. Each capability works on its own — denying one only disables that one.")
                .foregroundStyle(NaruColors.mutedInk)
            permission(
                icon: "figure.wave",
                title: "Accessibility — for text",
                detail: "Lets the helper insert composed text into the focused Mac app. Triggered by the "
                    + "`--request-text-permission` command."
            )
            permission(
                icon: "rectangle.on.rectangle",
                title: "Screen Recording — for video",
                detail: "Lets the helper stream your screen. Triggered by the `--request-permission` command."
            )
            Text("Basic VNC viewing needs neither permission. If you only want fast Korean text, grant Accessibility and skip Screen Recording.")
                .font(.callout)
                .foregroundStyle(NaruColors.mutedInk)
        }
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verify")
                .font(.title3.weight(.semibold))
            Text("Check that \(endpointLabel) is reachable. This confirms the Mac is up on your private network.")
                .foregroundStyle(NaruColors.mutedInk)

            if let onTestReachability {
                Button {
                    Task { await runReachabilityTest(onTestReachability) }
                } label: {
                    HStack {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text(isTesting ? "Testing…" : "Test connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting)
                .accessibilityIdentifier("naru.helper.onboarding.test")

                if let reachabilityMessage {
                    Text(reachabilityMessage)
                        .font(.callout)
                        .foregroundStyle(
                            state.verification.isPositive
                                ? AnyShapeStyle(NaruColors.reachable)
                                : AnyShapeStyle(NaruColors.coral)
                        )
                        .accessibilityIdentifier("naru.helper.onboarding.test.outcome")
                }
            } else {
                Text("Save this profile, then use its helper status to test the connection.")
                    .font(.callout)
                    .foregroundStyle(NaruColors.mutedInk)
            }

            Text("This test confirms the Mac is reachable. Full helper verification — pairing plus the Accessibility and Screen Recording permissions — is confirmed after you save, from the profile's helper status.")
                .font(.caption)
                .foregroundStyle(NaruColors.mutedInk)
                .padding(.top, 4)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Ready to save", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(NaruColors.reachable)
            Text("Finishing enables the helper on this profile and stages your pairing secret. It is saved to the device Keychain only when you tap Save on the profile — it is never stored on the profile itself.")
                .foregroundStyle(NaruColors.mutedInk)
            teardownNote
        }
    }

    private var teardownNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turning it off later")
                .font(.subheadline.weight(.semibold))
            Text("To pause the helper, turn its toggle off in the profile and Save — basic viewing keeps working. To rotate a leaked secret, run this setup again with Regenerate, or clear the helper token to revoke the pairing. Disabling stops fast video, confirmed text insert, and Live type-through fidelity.")
                .font(.caption)
                .foregroundStyle(NaruColors.mutedInk)
        }
        .padding(12)
        .background(NaruColors.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack {
            if state.step.previous != nil {
                Button("Back") { state.goBack() }
                    .accessibilityIdentifier("naru.helper.onboarding.back")
            }
            Spacer()
            Button(primaryButtonTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("naru.helper.onboarding.primary")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var primaryButtonTitle: String {
        switch state.step {
        case .intro: return "Get started"
        case .configure: return "Next"
        case .permissions: return "Next"
        case .verify: return "Next"
        case .done: return "Finish"
        }
    }

    // MARK: - Behavior

    private func advance() {
        switch state.step {
        case .intro:
            state.advance()
            ensureSecret()
        case .configure, .permissions, .verify:
            state.advance()
        case .done:
            finish()
        }
    }

    private func ensureSecret() {
        guard secret.isEmpty else { return }
        regenerateSecret()
    }

    private func regenerateSecret() {
        let newSecret = HelperPairingSecret.generate()
        secret = newSecret
        state.recordGeneratedSecret(fingerprint: HelperPairingSecret.fingerprint(for: newSecret))
        didCopySecret = false
        didCopyCommands = false
    }

    private func finish() {
        guard !secret.isEmpty, let fingerprint = state.fingerprint else {
            dismiss()
            return
        }
        onApply(
            HelperOnboardingResult(
                secret: secret,
                fingerprint: fingerprint,
                capabilities: state.capabilities
            )
        )
        didApply = true
        // Clear the transient secret from view state on the way out.
        secret = ""
        dismiss()
    }

    private func runReachabilityTest(
        _ runner: @MainActor (String, Int, String?) async -> ProfileEditorTestOutcome
    ) async {
        isTesting = true
        state.verification = .checking
        reachabilityMessage = nil
        let outcome = await runner(host, port, nil)
        reachabilityMessage = outcome.safeMessage
        state.verification = outcome.verdict == .failed ? .hostUnreachable : .hostReachable
        isTesting = false
    }

    /// Endpoint label for the verify copy.  `String(port)` avoids the
    /// locale grouping SwiftUI's `Text` interpolation applies to `Int`
    /// (which would render "5900" as "5,900").
    private var endpointLabel: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "your Mac"
            : "\(host):\(String(port))"
    }

    private var snippet: String {
        HelperOnboardingSnippet.build(
            fingerprint: state.fingerprint ?? HelperPairingSecret.fingerprint(for: secret),
            host: host,
            capabilities: state.capabilities
        )
    }

    // MARK: - Small view helpers

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(NaruColors.signalBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(NaruColors.mutedInk)
            }
        }
    }

    private func permission(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(NaruColors.signalBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(.init(detail)).font(.caption).foregroundStyle(NaruColors.mutedInk)
            }
        }
    }

    private func labeledMono(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(NaruColors.mutedInk)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
