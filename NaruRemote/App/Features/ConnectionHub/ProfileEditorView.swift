import NaruRemoteCore
import SwiftUI

public struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var host = ""
    @State private var port = "5900"
    @State private var password = ""
    @State private var hostKind = ConnectionProfile.HostKind.magicDNS
    @State private var allowsPiPWatch = true
    @State private var validationMessage: String?

    private let onSave: (ConnectionProfile, String?) -> Void

    public init(onSave: @escaping (ConnectionProfile, String?) -> Void) {
        self.onSave = onSave
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
                    SecureField("VNC password", text: $password)
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
            .navigationTitle("Add Profile")
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

    private func save() {
        guard let portValue = Int(port) else {
            validationMessage = "Port must be a number."
            return
        }

        do {
            let profileID = UUID()
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
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
