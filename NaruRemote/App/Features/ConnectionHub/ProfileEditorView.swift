import NaruRemoteCore
import SwiftUI

public struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var formState: ProfileEditorFormState
    @State private var password: String
    @State private var hostKind: ConnectionProfile.HostKind
    @State private var allowsPiPWatch: Bool
    @State private var replacePassword: Bool
    @State private var validationMessage: String?

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

    private let editingProfile: ConnectionProfile?
    private let hasExistingCredential: Bool
    private let onSave: (ConnectionProfile, String?) -> Void
    /// Reachability-check runner injected by the SwiftUI wiring.  In
    /// production the shell passes
    /// `model.runProfileEditorReachabilityTest`; tests pass a stub.
    /// Optional so `#Preview` and prior call sites that did not need
    /// the Test affordance can omit it (the button hides when `nil`).
    private let onTest: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)?

    private enum Field: Hashable {
        case displayName
        case host
        case port
        case password
    }

    /// Add-mode initializer — fields start empty and the password
    /// box, when non-empty, becomes the new keychain credential.
    public init(
        onTest: (@MainActor (String, Int, String?) async -> ProfileEditorTestOutcome)? = nil,
        onSave: @escaping (ConnectionProfile, String?) -> Void
    ) {
        self.editingProfile = nil
        self.hasExistingCredential = false
        self.onSave = onSave
        self.onTest = onTest
        _formState = State(initialValue: ProfileEditorFormState())
        _password = State(initialValue: "")
        _hostKind = State(initialValue: .magicDNS)
        _allowsPiPWatch = State(initialValue: true)
        // In add mode the toggle is irrelevant; treat it as "on" so
        // an empty password box maps to "no credential" via the
        // existing add-mode rule.
        _replacePassword = State(initialValue: true)
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
        onSave: @escaping (ConnectionProfile, String?) -> Void
    ) {
        self.editingProfile = profile
        self.hasExistingCredential = hasExistingCredential
        self.onSave = onSave
        self.onTest = onTest
        _formState = State(initialValue: ProfileEditorFormState(
            displayName: profile.displayName,
            host: profile.host,
            port: String(profile.port)
        ))
        _password = State(initialValue: "")
        _hostKind = State(initialValue: profile.hostKind)
        _allowsPiPWatch = State(initialValue: profile.allowsPiPWatch)
        // Default off when there is an existing credential — the
        // safest choice is to leave the saved password alone unless
        // the user explicitly opts in to replacing it.  When there
        // is no existing credential the field is just an add-style
        // password box.
        _replacePassword = State(initialValue: !hasExistingCredential)
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
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!formState.isValid)
                }
            }
            .onChange(of: focusedField) { previous, _ in
                // Mark the field the focus just left as "touched" so
                // its inline error caption can render after blur.
                if let previous {
                    touchedFields.insert(previous)
                }
            }
        }
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

    private var passwordPlaceholder: String {
        if isEditing && hasExistingCredential && replacePassword {
            return "New VNC password (empty to clear)"
        }
        return "VNC password"
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

    private func save() {
        saveAttemptCount += 1
        guard formState.isValid, let portValue = formState.parsedPort else {
            return
        }

        do {
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPassword: String?
            let credentialRef: String?

            if let editingProfile {
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
                    allowsPiPWatch: allowsPiPWatch
                )
                onSave(profile, resolvedPassword)
                dismiss()
                return
            }

            let profileID = UUID()
            let profile = try ConnectionProfile(
                id: profileID,
                displayName: formState.displayName,
                host: formState.host,
                port: portValue,
                credentialRef: trimmedPassword.isEmpty ? nil : "vnc-password:\(profileID.uuidString)",
                hostKind: hostKind,
                allowsPiPWatch: allowsPiPWatch
            )
            onSave(profile, trimmedPassword.isEmpty ? nil : trimmedPassword)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
