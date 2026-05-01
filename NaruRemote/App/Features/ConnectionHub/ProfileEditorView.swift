import NaruRemoteCore
import SwiftUI

public struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var host: String
    @State private var port: String
    @State private var password: String
    @State private var hostKind: ConnectionProfile.HostKind
    @State private var allowsPiPWatch: Bool
    @State private var replacePassword: Bool
    @State private var validationMessage: String?

    private let editingProfile: ConnectionProfile?
    private let hasExistingCredential: Bool
    private let onSave: (ConnectionProfile, String?) -> Void

    /// Add-mode initializer — fields start empty and the password
    /// box, when non-empty, becomes the new keychain credential.
    public init(onSave: @escaping (ConnectionProfile, String?) -> Void) {
        self.editingProfile = nil
        self.hasExistingCredential = false
        self.onSave = onSave
        _displayName = State(initialValue: "")
        _host = State(initialValue: "")
        _port = State(initialValue: "5900")
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
        onSave: @escaping (ConnectionProfile, String?) -> Void
    ) {
        self.editingProfile = profile
        self.hasExistingCredential = hasExistingCredential
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName)
        _host = State(initialValue: profile.host)
        _port = State(initialValue: String(profile.port))
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
                    TextField("Profile name", text: $displayName)
                    TextField("MagicDNS or private host", text: $host)
                    TextField("Port", text: $port)
                }

                Section("Credentials") {
                    if isEditing && hasExistingCredential {
                        Toggle("Replace password", isOn: $replacePassword)
                            .accessibilityIdentifier("naru.profile.editor.replacePassword")
                    }

                    if shouldShowPasswordField {
                        SecureField(passwordPlaceholder, text: $password)
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

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
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
                }
            }
        }
        .accessibilityIdentifier("naru.profile.editor")
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

    private func save() {
        guard let portValue = Int(port) else {
            validationMessage = "Port must be a number."
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
                    displayName: displayName,
                    host: host,
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
                displayName: displayName,
                host: host,
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
