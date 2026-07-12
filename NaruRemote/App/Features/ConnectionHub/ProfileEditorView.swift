import Foundation
import NaruRemoteCore
import SwiftUI

public struct ProfileEditorCredentialUpdate: Equatable, Sendable {
    public var vncPassword: String?
    public var helperPairingSecret: String?
    public var helperVideoPairingSecret: String?

    public init(
        vncPassword: String? = nil,
        helperPairingSecret: String? = nil,
        helperVideoPairingSecret: String? = nil
    ) {
        self.vncPassword = vncPassword
        self.helperPairingSecret = helperPairingSecret
        self.helperVideoPairingSecret = helperVideoPairingSecret
    }
}

public struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var formState: ProfileEditorFormState
    @State private var password: String
    @State private var helperPairingSecret: String
    @State private var helperVideoPairingSecret: String
    @State private var hostKind: ConnectionProfile.HostKind
    @State private var allowsPiPWatch: Bool
    @State private var replacePassword: Bool
    @State private var replaceHelperPairingSecret: Bool
    @State private var replaceHelperVideoPairingSecret: Bool
    @State private var validationMessage: String?
    @State private var persistenceFailure: ProfilePersistenceFailure?
    @State private var isSaving: Bool = false

    /// Bumped on every Save tap so the field-level captions appear
    /// after the user has at least once asked to commit the form,
    /// avoiding "name is required" from showing on a fresh empty
    /// editor before the user has touched anything.
    @State private var saveAttemptCount: Int = 0

    /// Set of fields the user has visited and left (lost focus).
    /// Drives the "show error after the user has interacted with
    /// the field" rule so the empty-form first paint is calm.
    @State private var touchedFields: Set<Field> = []

    @FocusState private var focusedField: Field?

    /// In-flight + most-recent reachability-test outcome from the
    /// "Test" affordance.  Constitution §IV: `outcome.safeMessage`
    /// originates from `DiagnosticMessageCatalog` — never from a raw
    /// network error.
    @State private var testOutcome: ProfileEditorTestOutcome?
    @State private var isTesting: Bool = false

    /// Presents the guided Naru Helper onboarding sheet (spec 010).
    @State private var showsHelperOnboarding: Bool = false

    private let editingProfile: ConnectionProfile?
    private let hasExistingCredential: Bool
    private let hasExistingHelperPairingSecret: Bool
    private let hasExistingHelperVideoPairingSecret: Bool
    /// Returns a task so the existing shell wiring can hand back its
    /// unstructured `Task { await model.add/editProfile(...) }` without owning
    /// sheet dismissal. The editor awaits the task and dismisses only after a
    /// successful durable profile write.
    private let onSave: @MainActor (
        ConnectionProfile,
        ProfileEditorCredentialUpdate
    ) -> Task<ProfilePersistenceResult, Never>
    /// Reachability-check runner injected by the SwiftUI wiring.  In
    /// production the shell passes
    /// `model.runProfileEditorReachabilityTest`; tests pass a stub.
    /// Optional so `#Preview` and prior call sites that did not need
    /// the Test affordance can omit it (the button hides when `nil`).
    private let onTest: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)?
    /// Optional in-flow helper-handshake test for the onboarding verify
    /// step (spec 010 FR-013).  Absent today: the shell passes the
    /// editor only closures and there is no view-reachable single-profile
    /// helper probe wired yet.  When wired it returns the profile's
    /// helper availability so the verify step can reflect pairing +
    /// permission state, not just host reachability.
    private let onTestHelper: (@MainActor () async -> HelperTextBridgeAvailability)?

    private enum Field: Hashable {
        case displayName
        case host
        case port
        case password
        case helperHost
        case helperPort
        case helperPairingSecret
        case helperVideoPairingSecret
    }

    /// Add-mode initializer — fields start empty and the password
    /// box, when non-empty, becomes the new keychain credential.
    public init(
        onTest: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)? = nil,
        onTestHelper: (@MainActor () async -> HelperTextBridgeAvailability)? = nil,
        onSave: @escaping @MainActor (
            ConnectionProfile,
            ProfileEditorCredentialUpdate
        ) -> Task<ProfilePersistenceResult, Never>
    ) {
        self.editingProfile = nil
        self.hasExistingCredential = false
        self.hasExistingHelperPairingSecret = false
        self.hasExistingHelperVideoPairingSecret = false
        self.onSave = onSave
        self.onTest = onTest
        self.onTestHelper = onTestHelper
        _formState = State(initialValue: ProfileEditorFormState())
        _password = State(initialValue: "")
        _helperPairingSecret = State(initialValue: "")
        _helperVideoPairingSecret = State(initialValue: "")
        _hostKind = State(initialValue: .magicDNS)
        _allowsPiPWatch = State(initialValue: true)
        // In add mode the toggle is irrelevant; treat it as "on" so
        // an empty password box maps to "no credential" via the
        // existing add-mode rule.
        _replacePassword = State(initialValue: true)
        _replaceHelperPairingSecret = State(initialValue: true)
        _replaceHelperVideoPairingSecret = State(initialValue: true)
    }

    /// Edit-mode initializer — fields are pre-filled from the
    /// existing profile.  The keychain password is **never**
    /// pre-filled.  When `hasExistingCredential` is `true` a
    /// "Replace password" toggle defaults to off, meaning the
    /// existing credential stays untouched (`onSave` receives
    /// `password: nil`).  Flipping the toggle reveals a `SecureField`
    /// where:
    ///   * empty box  → clear the saved password (`""`)
    ///   * filled box → save a new password
    /// When `hasExistingCredential` is `false` the toggle is hidden
    /// and the password field behaves like add mode.
    public init(
        editing profile: ConnectionProfile,
        hasExistingCredential: Bool,
        onTest: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)? = nil,
        onTestHelper: (@MainActor () async -> HelperTextBridgeAvailability)? = nil,
        onSave: @escaping @MainActor (
            ConnectionProfile,
            ProfileEditorCredentialUpdate
        ) -> Task<ProfilePersistenceResult, Never>
    ) {
        self.editingProfile = profile
        self.hasExistingCredential = hasExistingCredential
        self.hasExistingHelperPairingSecret = profile.helperTextBridge?.pairingSecretRef != nil
        self.hasExistingHelperVideoPairingSecret = profile.helperVideo?.pairingSecretRef != nil
        self.onSave = onSave
        self.onTest = onTest
        self.onTestHelper = onTestHelper
        let helperConfig = profile.helperTextBridge
        _formState = State(initialValue: ProfileEditorFormState(
            displayName: profile.displayName,
            host: profile.host,
            port: String(profile.port),
            helperTextBridgeEnabled: helperConfig?.isEnabled ?? false,
            helperHost: helperConfig?.host ?? "",
            helperPort: String(helperConfig?.port ?? naruHelperTextBridgeDefaultPort),
            helperVideoEnabled: profile.helperVideo?.isEnabled ?? false
        ))
        _password = State(initialValue: "")
        _helperPairingSecret = State(initialValue: "")
        _helperVideoPairingSecret = State(initialValue: "")
        _hostKind = State(initialValue: profile.hostKind)
        _allowsPiPWatch = State(initialValue: profile.allowsPiPWatch)
        // Default off when there is an existing credential — the
        // safest choice is to leave the saved password alone unless
        // the user explicitly opts in to replacing it.  When there
        // is no existing credential the field is just an add-style
        // password box.
        _replacePassword = State(initialValue: !hasExistingCredential)
        _replaceHelperPairingSecret = State(initialValue: profile.helperTextBridge?.pairingSecretRef == nil)
        _replaceHelperVideoPairingSecret = State(initialValue: profile.helperVideo?.pairingSecretRef == nil)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Private target") {
                    TextField("Profile name", text: $formState.displayName)
                        .focused($focusedField, equals: .displayName)
                        .accessibilityIdentifier("naru.profile.editor.name")
                    if shouldShowError(for: .displayName), let message = formState.displayNameError {
                        captionView(message)
                            .accessibilityIdentifier("naru.profile.editor.name.error")
                    }

                    TextField("MagicDNS or private host", text: $formState.host)
                        .focused($focusedField, equals: .host)
                        .accessibilityIdentifier("naru.profile.editor.host")
                    if shouldShowError(for: .host), let message = formState.hostError {
                        captionView(message)
                            .accessibilityIdentifier("naru.profile.editor.host.error")
                    }

                    LabeledContent("Port") {
                        portField
                    }
                    if shouldShowError(for: .port), let message = formState.portError {
                        captionView(message)
                            .accessibilityIdentifier("naru.profile.editor.port.error")
                    }
                }

                Section("Credentials") {
                    if isEditing && hasExistingCredential {
                        Toggle("Replace password", isOn: $replacePassword)
                            .accessibilityIdentifier("naru.profile.editor.replacePassword")
                    }

                    if shouldShowPasswordField {
                        SecureField(passwordPlaceholder, text: $password)
                            .focused($focusedField, equals: .password)
                            // `.oneTimeCode` is intentional — not because
                            // this is an SMS code, but because it's the
                            // standard way to opt this field out of iOS
                            // iCloud Keychain's "Save Password?" prompt.
                            // VNC credentials live exclusively in Naru
                            // Remote's own Keychain (via `credentialRef`)
                            // per the constitution; offering iCloud
                            // Keychain a second copy would create two
                            // sources of truth that drift.  `.password`
                            // and `.newPassword` both surface that
                            // prompt; `.oneTimeCode` is the documented
                            // suppression pattern.
                            .textContentType(.oneTimeCode)
                            .accessibilityIdentifier("naru.profile.editor.password")
                    } else {
                        Text("Saved password kept")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Network posture") {
                    Picker("Host type", selection: $hostKind) {
                        Text("MagicDNS").tag(ConnectionProfile.HostKind.magicDNS)
                        Text("Private address").tag(ConnectionProfile.HostKind.privateAddress)
                        Text("Advanced public").tag(ConnectionProfile.HostKind.advancedManualPublicEndpoint)
                    }
                    Toggle("Allow PiP Watch", isOn: $allowsPiPWatch)
                }

                if hostKind != .advancedManualPublicEndpoint {
                    Section("Naru Helper") {
                        Text("Fast video, confirmed Korean text, and Live type-through need a small helper on your Mac. Basic viewing works without it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            showsHelperOnboarding = true
                        } label: {
                            Label("Set up Naru Helper", systemImage: "wand.and.stars")
                        }
                        .accessibilityIdentifier("naru.profile.editor.helper.setup")
                    }
                }

                Section("Helper text bridge") {
                    Toggle("Enable helper text bridge", isOn: $formState.helperTextBridgeEnabled)
                        .accessibilityIdentifier("naru.profile.editor.helper.enabled")

                    if formState.helperTextBridgeEnabled {
                        TextField("Helper host (blank uses VNC host)", text: $formState.helperHost)
                            .focused($focusedField, equals: .helperHost)
                            .accessibilityIdentifier("naru.profile.editor.helper.host")

                        LabeledContent("Helper port") {
                            helperPortField
                        }
                        if shouldShowError(for: .helperPort), let message = formState.helperPortError {
                            captionView(message)
                                .accessibilityIdentifier("naru.profile.editor.helper.port.error")
                        }

                        if isEditing && hasExistingHelperPairingSecret {
                            Toggle("Replace helper token", isOn: $replaceHelperPairingSecret)
                                .accessibilityIdentifier("naru.profile.editor.helper.replaceToken")
                        }

                        if shouldShowHelperPairingSecretField {
                            SecureField(helperPairingSecretPlaceholder, text: $helperPairingSecret)
                                .focused($focusedField, equals: .helperPairingSecret)
                                .textContentType(.oneTimeCode)
                                .accessibilityIdentifier("naru.profile.editor.helper.token")
                        } else {
                            Text("Saved helper token kept")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Helper video") {
                    Toggle("Enable helper video", isOn: $formState.helperVideoEnabled)
                        .accessibilityIdentifier("naru.profile.editor.helperVideo.enabled")

                    if formState.helperVideoEnabled {
                        if isEditing && hasExistingHelperVideoPairingSecret {
                            Toggle("Replace helper video token", isOn: $replaceHelperVideoPairingSecret)
                                .accessibilityIdentifier("naru.profile.editor.helperVideo.replaceToken")
                        }

                        if shouldShowHelperVideoPairingSecretField {
                            SecureField(helperVideoPairingSecretPlaceholder, text: $helperVideoPairingSecret)
                                .focused($focusedField, equals: .helperVideoPairingSecret)
                                .textContentType(.oneTimeCode)
                                .accessibilityIdentifier("naru.profile.editor.helperVideo.token")
                        } else {
                            Text("Saved helper video token kept")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if onTest != nil {
                    Section("Reachability") {
                        Button {
                            Task { await runTest() }
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isTesting ? "Testing..." : "Test")
                            }
                        }
                        .disabled(isTesting || !canTest)
                        .accessibilityIdentifier("naru.profile.editor.test")

                        if let testOutcome {
                            Text(testOutcome.safeMessage)
                                .font(.caption)
                                .foregroundStyle(testOutcome.verdict == .failed ? AnyShapeStyle(NaruColors.coral) : AnyShapeStyle(.secondary))
                                .accessibilityIdentifier("naru.profile.editor.test.outcome")
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(NaruColors.coral)
                    }
                }

                if let persistenceFailure {
                    Section("Save failed") {
                        Label(
                            persistenceFailure.safeMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(NaruColors.coral)
                        .accessibilityIdentifier("naru.profile.editor.persistence.error")

                        Button("Try Again") {
                            Task { await save() }
                        }
                        .disabled(isSaving)
                        .accessibilityIdentifier("naru.profile.editor.persistence.retry")
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving profile")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!formState.isValid || isSaving)
                    .accessibilityIdentifier("naru.profile.editor.save")
                }
            }
            .onChange(of: focusedField) { previous, _ in
                // Mark the field the focus just left as "touched" so
                // its inline error caption can render after blur.
                if let previous {
                    touchedFields.insert(previous)
                }
            }
            .onAppear {
                if !isEditing {
                    focusedField = .host
                }
            }
            .sheet(isPresented: $showsHelperOnboarding) {
                HelperOnboardingView(
                    host: formState.host,
                    port: formState.parsedPort ?? 5900,
                    existingFingerprint: editingProfile?.helperTextBridge?.pairingFingerprint,
                    onTestReachability: onTest,
                    onTestHelper: onTestHelper,
                    onApply: applyHelperOnboarding
                )
            }
        }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("naru.profile.editor")
    }

    /// Port `TextField` extracted so the iOS-only `.keyboardType` /
    /// `.multilineTextAlignment` modifiers can be conditionally
    /// compiled out of macOS builds (the SwiftPM `NaruRemoteApp`
    /// target builds on both platforms; macOS lacks `keyboardType`).
    @ViewBuilder
    private var portField: some View {
        #if os(iOS)
        TextField("Port", text: $formState.port)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: .port)
            .accessibilityIdentifier("naru.profile.editor.port")
        #else
        TextField("Port", text: $formState.port)
            .focused($focusedField, equals: .port)
            .accessibilityIdentifier("naru.profile.editor.port")
        #endif
    }

    @ViewBuilder
    private var helperPortField: some View {
        #if os(iOS)
        TextField("Helper port", text: $formState.helperPort)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focusedField, equals: .helperPort)
            .accessibilityIdentifier("naru.profile.editor.helper.port")
        #else
        TextField("Helper port", text: $formState.helperPort)
            .focused($focusedField, equals: .helperPort)
            .accessibilityIdentifier("naru.profile.editor.helper.port")
        #endif
    }

    private var isEditing: Bool {
        editingProfile != nil
    }

    private var navigationTitle: String {
        isEditing ? "Edit Profile" : "Add Profile"
    }

    /// True when the password `SecureField` should render.  In add
    /// mode it always renders.  In edit mode it renders when there
    /// is no existing credential, or when the user has flipped the
    /// "Replace password" toggle on.
    private var shouldShowPasswordField: Bool {
        if !isEditing {
            return true
        }
        if !hasExistingCredential {
            return true
        }
        return replacePassword
    }

    private var shouldShowHelperPairingSecretField: Bool {
        guard formState.helperTextBridgeEnabled else {
            return false
        }
        if !isEditing {
            return true
        }
        if !hasExistingHelperPairingSecret {
            return true
        }
        return replaceHelperPairingSecret
    }

    private var shouldShowHelperVideoPairingSecretField: Bool {
        guard formState.helperVideoEnabled else {
            return false
        }
        if !isEditing {
            return true
        }
        if !hasExistingHelperVideoPairingSecret {
            return true
        }
        return replaceHelperVideoPairingSecret
    }

    private var passwordPlaceholder: String {
        if isEditing && hasExistingCredential && replacePassword {
            return "New VNC password (empty to clear)"
        }
        return "VNC password"
    }

    private var helperPairingSecretPlaceholder: String {
        if isEditing && hasExistingHelperPairingSecret && replaceHelperPairingSecret {
            return "New helper token"
        }
        return "Helper token"
    }

    private var helperVideoPairingSecretPlaceholder: String {
        if isEditing && hasExistingHelperVideoPairingSecret && replaceHelperVideoPairingSecret {
            return "New helper video token"
        }
        return "Helper video token"
    }

    /// The Test affordance only requires a non-empty host and a
    /// port in range — `displayName` is irrelevant to reachability,
    /// so the user can verify a candidate host before naming it.
    private var canTest: Bool {
        formState.hostError == nil && formState.portError == nil
    }

    private func shouldShowError(for field: Field) -> Bool {
        // After a Save attempt all errors surface so the user knows
        // why Save is disabled.  Before that, only fields the user
        // has already focused-and-left show an error.
        saveAttemptCount > 0 || touchedFields.contains(field)
    }

    @ViewBuilder
    private func captionView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(NaruColors.coral)
    }

    private func runTest() async {
        guard let onTest else { return }
        guard let portValue = formState.parsedPort else { return }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordToUse: String?
        if !shouldShowPasswordField {
            // Edit mode with an existing credential and the toggle
            // off — the Test affordance does not load the saved
            // password (constitution §IV: secrets stay in keychain
            // and never round-trip through this view), so the test
            // runs as no-auth.  A success-with-password-required
            // verdict still tells the user the host is reachable.
            passwordToUse = nil
        } else {
            passwordToUse = trimmedPassword.isEmpty ? nil : trimmedPassword
        }

        isTesting = true
        testOutcome = nil
        let outcome = await onTest(formState.host, portValue, passwordToUse)
        // Guard against view dismiss races: only update state if the
        // view is still mounted (SwiftUI handles this for `@State`
        // automatically — assigning after a dismiss is a no-op).
        testOutcome = outcome
        isTesting = false
    }

    /// Stage the secret the onboarding generated into the editor's
    /// existing fields so the next Save persists it through the normal
    /// `ProfileEditorCredentialUpdate` → Keychain path (spec 010 FR-012;
    /// constitution §IV — the secret never touches `ConnectionProfile`
    /// or the file store).  In v1 one secret pairs both text and video.
    private func applyHelperOnboarding(_ result: HelperOnboardingResult) {
        if result.capabilities.text {
            helperPairingSecret = result.secret
            formState.helperTextBridgeEnabled = true
            replaceHelperPairingSecret = true
        }
        if result.capabilities.video {
            helperVideoPairingSecret = result.secret
            formState.helperVideoEnabled = true
            replaceHelperVideoPairingSecret = true
        }
    }

    private func resolveHelperTextBridge(
        profileID: ConnectionProfile.ID,
        existingConfiguration: HelperTextBridgeConnectionConfiguration?
    ) throws -> (
        configuration: HelperTextBridgeConnectionConfiguration?,
        pairingSecretUpdate: String?
    ) {
        if !formState.helperTextBridgeEnabled {
            return (
                configuration: nil,
                pairingSecretUpdate: existingConfiguration?.pairingSecretRef == nil ? nil : ""
            )
        }

        guard let helperPort = formState.parsedHelperPort else {
            throw ProfileEditorValidationError.invalidHelperPort
        }

        let trimmedSecret = helperPairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretRef: String
        let secretUpdate: String?
        let fingerprint: String?

        if isEditing && hasExistingHelperPairingSecret && !replaceHelperPairingSecret {
            guard let existingRef = existingConfiguration?.pairingSecretRef else {
                throw ProfileEditorValidationError.helperTokenRequired
            }
            secretRef = existingRef
            secretUpdate = nil
            fingerprint = existingConfiguration?.pairingFingerprint
        } else {
            guard !trimmedSecret.isEmpty else {
                throw ProfileEditorValidationError.helperTokenRequired
            }
            secretRef = existingConfiguration?.pairingSecretRef
                ?? Self.helperPairingSecretReference(for: profileID)
            secretUpdate = trimmedSecret
            fingerprint = Self.pairingFingerprint(for: trimmedSecret)
        }

        return (
            configuration: try HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                host: formState.helperHost,
                port: helperPort,
                pairingSecretRef: secretRef,
                pairingFingerprint: fingerprint
            ),
            pairingSecretUpdate: secretUpdate
        )
    }

    private func resolveHelperVideo(
        profileID: ConnectionProfile.ID,
        existingConfiguration: HelperVideoConnectionConfiguration?
    ) throws -> (
        configuration: HelperVideoConnectionConfiguration?,
        pairingSecretUpdate: String?
    ) {
        if !formState.helperVideoEnabled {
            guard let existingConfiguration else {
                return (configuration: nil, pairingSecretUpdate: nil)
            }
            return (
                configuration: HelperVideoConnectionConfiguration(
                    isEnabled: false,
                    isRevoked: false,
                    pairingSecretRef: existingConfiguration.pairingSecretRef,
                    pairingFingerprint: existingConfiguration.pairingFingerprint
                ),
                pairingSecretUpdate: nil
            )
        }

        let trimmedSecret = helperVideoPairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretRef: String
        let secretUpdate: String?
        let fingerprint: String?

        if isEditing && hasExistingHelperVideoPairingSecret && !replaceHelperVideoPairingSecret {
            guard let existingRef = existingConfiguration?.pairingSecretRef else {
                throw ProfileEditorValidationError.helperVideoTokenRequired
            }
            secretRef = existingRef
            secretUpdate = nil
            fingerprint = existingConfiguration?.pairingFingerprint
        } else {
            guard !trimmedSecret.isEmpty else {
                throw ProfileEditorValidationError.helperVideoTokenRequired
            }
            secretRef = existingConfiguration?.pairingSecretRef
                ?? Self.helperVideoPairingSecretReference(for: profileID)
            secretUpdate = trimmedSecret
            fingerprint = Self.pairingFingerprint(for: trimmedSecret)
        }

        return (
            configuration: HelperVideoConnectionConfiguration(
                isEnabled: true,
                isRevoked: false,
                pairingSecretRef: secretRef,
                pairingFingerprint: fingerprint
            ),
            pairingSecretUpdate: secretUpdate
        )
    }

    private func save() async {
        guard !isSaving else {
            return
        }
        saveAttemptCount += 1
        guard formState.isValid, let portValue = formState.parsedPort else {
            return
        }
        validationMessage = nil
        persistenceFailure = nil

        do {
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPassword: String?
            let credentialRef: String?

            if let editingProfile {
                let helper = try resolveHelperTextBridge(
                    profileID: editingProfile.id,
                    existingConfiguration: editingProfile.helperTextBridge
                )
                let helperVideo = try resolveHelperVideo(
                    profileID: editingProfile.id,
                    existingConfiguration: editingProfile.helperVideo
                )

                if hasExistingCredential && !replacePassword {
                    // Toggle is off → keep the keychain credential
                    // untouched.  Pass `nil` to the model so the
                    // existing entry is preserved.
                    resolvedPassword = nil
                    credentialRef = editingProfile.credentialRef
                } else if trimmedPassword.isEmpty {
                    // User opted to replace and left the box empty
                    // — treat as explicit clear.
                    resolvedPassword = ""
                    credentialRef = nil
                } else {
                    resolvedPassword = trimmedPassword
                    credentialRef = editingProfile.credentialRef ?? "vnc-password:\(editingProfile.id.uuidString)"
                }

                let profile = try ConnectionProfile(
                    id: editingProfile.id,
                    displayName: formState.displayName,
                    host: formState.host,
                    port: portValue,
                    username: editingProfile.username,
                    credentialRef: credentialRef,
                    favorite: editingProfile.favorite,
                    lastConnectedAt: editingProfile.lastConnectedAt,
                    lastDiagnosticSummary: editingProfile.lastDiagnosticSummary,
                    hostKind: hostKind,
                    allowsPiPWatch: allowsPiPWatch,
                    helperTextBridge: helper.configuration,
                    helperVideo: helperVideo.configuration
                )
                await persist(
                    profile,
                    ProfileEditorCredentialUpdate(
                        vncPassword: resolvedPassword,
                        helperPairingSecret: helper.pairingSecretUpdate,
                        helperVideoPairingSecret: helperVideo.pairingSecretUpdate
                    )
                )
                return
            }

            let profileID = UUID()
            let helper = try resolveHelperTextBridge(
                profileID: profileID,
                existingConfiguration: nil
            )
            let helperVideo = try resolveHelperVideo(
                profileID: profileID,
                existingConfiguration: nil
            )
            let profile = try ConnectionProfile(
                id: profileID,
                displayName: formState.displayName,
                host: formState.host,
                port: portValue,
                credentialRef: trimmedPassword.isEmpty ? nil : "vnc-password:\(profileID.uuidString)",
                hostKind: hostKind,
                allowsPiPWatch: allowsPiPWatch,
                helperTextBridge: helper.configuration,
                helperVideo: helperVideo.configuration
            )
            await persist(
                profile,
                ProfileEditorCredentialUpdate(
                    vncPassword: trimmedPassword.isEmpty ? nil : trimmedPassword,
                    helperPairingSecret: helper.pairingSecretUpdate,
                    helperVideoPairingSecret: helperVideo.pairingSecretUpdate
                )
            )
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func persist(
        _ profile: ConnectionProfile,
        _ credentialUpdate: ProfileEditorCredentialUpdate
    ) async {
        isSaving = true
        let result = await onSave(profile, credentialUpdate).value
        isSaving = false

        switch result {
        case .succeeded:
            dismiss()
        case .failed(let failure):
            // `failure` is a fixed catalog value from the app model. Never
            // surface a raw persistence error, host, credential, or payload.
            persistenceFailure = failure
        }
    }

    private static func helperPairingSecretReference(for profileID: ConnectionProfile.ID) -> String {
        "helper-token:\(profileID.uuidString)"
    }

    private static func helperVideoPairingSecretReference(for profileID: ConnectionProfile.ID) -> String {
        "helper-video-token:\(profileID.uuidString)"
    }

    private static func pairingFingerprint(for secret: String) -> String {
        // Single source of truth with the onboarding flow (spec 010
        // FR-005): the fingerprint shown during setup must equal the one
        // persisted here for the same secret.
        HelperPairingSecret.fingerprint(for: secret)
    }
}

private enum ProfileEditorValidationError: LocalizedError {
    case invalidHelperPort
    case helperTokenRequired
    case helperVideoTokenRequired

    var errorDescription: String? {
        switch self {
        case .invalidHelperPort:
            "Helper port must be between 1 and 65535."
        case .helperTokenRequired:
            "Helper token is required when helper text bridge is enabled."
        case .helperVideoTokenRequired:
            "Helper video token is required when helper video is enabled."
        }
    }
}
