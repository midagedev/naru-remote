import NaruRemoteCore
import SwiftUI

public struct ProfileListView: View {
    private let profiles: [ConnectionProfile]
    private let selectedProfileID: ConnectionProfile.ID?
    private let onSelect: (ConnectionProfile.ID) -> Void

    public init(
        profiles: [ConnectionProfile],
        selectedProfileID: ConnectionProfile.ID? = nil,
        onSelect: @escaping (ConnectionProfile.ID) -> Void = { _ in }
    ) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.onSelect = onSelect
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
                }
            }
        }
        .accessibilityIdentifier("naru.profile.list")
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
