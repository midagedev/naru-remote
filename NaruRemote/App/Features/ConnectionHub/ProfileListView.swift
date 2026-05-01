import NaruRemoteCore
import SwiftUI

public struct ProfileListView: View {
    private let profiles: [ConnectionProfile]
    private let selectedProfileID: ConnectionProfile.ID?
    private let onSelect: (ConnectionProfile.ID) -> Void
    private let onEdit: (ConnectionProfile) -> Void
    private let onDelete: (ConnectionProfile.ID) -> Void

    /// Profile awaiting a destructive-confirm alert before delete.
    /// Held locally so the alert can display the user-facing name
    /// without re-resolving it from the model.
    @State private var pendingDeleteProfile: ConnectionProfile?

    public init(
        profiles: [ConnectionProfile],
        selectedProfileID: ConnectionProfile.ID? = nil,
        onSelect: @escaping (ConnectionProfile.ID) -> Void = { _ in },
        onEdit: @escaping (ConnectionProfile) -> Void = { _ in },
        onDelete: @escaping (ConnectionProfile.ID) -> Void = { _ in }
    ) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        List {
            if profiles.isEmpty {
                Text("Add a private VNC profile")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profiles) { profile in
                    Button {
                        onSelect(profile.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.hostKind.symbolName)
                                .foregroundStyle(.teal)
                                .frame(width: 24)
                                .help(profile.hostKind.accessibilityLabel)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName)
                                    .font(.headline)
                                Text(profile.endpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            if profile.id == selectedProfileID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("Selected profile")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            onEdit(profile)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                        .accessibilityIdentifier("naru.profile.row.edit")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteProfile = profile
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("naru.profile.row.delete")
                    }
                    .contextMenu {
                        // The context-menu mirrors swipe actions for
                        // accessibility (VoiceOver / Switch Control)
                        // and split-view / mouse / keyboard users on
                        // iPad where swipe gestures are awkward.
                        Button {
                            onEdit(profile)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            pendingDeleteProfile = profile
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("naru.profile.list")
        .alert(
            "Delete profile?",
            isPresented: Binding(
                get: { pendingDeleteProfile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteProfile = nil
                    }
                }
            ),
            presenting: pendingDeleteProfile
        ) { profile in
            Button("Delete", role: .destructive) {
                onDelete(profile.id)
                pendingDeleteProfile = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteProfile = nil
            }
        } message: { _ in
            Text("This removes the saved password.")
        }
    }
}

private extension ConnectionProfile.HostKind {
    var symbolName: String {
        switch self {
        case .magicDNS:
            return "network"
        case .privateAddress:
            return "lock.display"
        case .advancedManualPublicEndpoint:
            return "exclamationmark.triangle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .magicDNS:
            return "MagicDNS host"
        case .privateAddress:
            return "Private address"
        case .advancedManualPublicEndpoint:
            return "Advanced public endpoint"
        }
    }
}
