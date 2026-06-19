import NaruRemoteCore
import SwiftUI

public struct ProfileListView: View {
    private let profiles: [ConnectionProfile]
    private let selectedProfileID: ConnectionProfile.ID?
    private let verdicts: [ConnectionProfile.ID: DiagnosticVerdict]
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
        verdicts: [ConnectionProfile.ID: DiagnosticVerdict] = [:],
        onSelect: @escaping (ConnectionProfile.ID) -> Void = { _ in },
        onEdit: @escaping (ConnectionProfile) -> Void = { _ in },
        onDelete: @escaping (ConnectionProfile.ID) -> Void = { _ in }
    ) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.verdicts = verdicts
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
                    let isSelected = profile.id == selectedProfileID
                    let isPublicEndpoint = profile.hostKind == .advancedManualPublicEndpoint
                    let verdict = verdicts[profile.id] ?? .unknown

                    Button {
                        onSelect(profile.id)
                    } label: {
                        HStack(spacing: 12) {
                            // Leading status dot — at-a-glance reachability cue
                            // (UX punch-list #109).  Sourced from the
                            // memory-only `lastDiagnosticVerdict` cache on the
                            // app model; defaults to `.unknown` (gray) when no
                            // diagnostic has run for this profile yet.
                            ProfileStatusDot(verdict: verdict)
                                .accessibilityIdentifier(
                                    "naru.profile.row.status.\(verdict.rawValue)"
                                )

                            Image(systemName: profile.hostKind.symbolName)
                                .foregroundStyle(
                                    isPublicEndpoint
                                        ? NaruColors.coral
                                        : NaruColors.mutedInk
                                )
                                .frame(width: 24)
                                .help(profile.hostKind.accessibilityLabel)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName)
                                    .font(
                                        isSelected
                                            ? .headline.weight(.semibold)
                                            : .headline
                                    )
                                Text(profile.endpoint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if isPublicEndpoint {
                                    // Constitution §II + BRANDING.md §7:
                                    // public VNC must show an explicit
                                    // warning, not a single bare icon.  Coral
                                    // caption sits directly under the host:port
                                    // line so a phone-screen scan can never
                                    // miss it.
                                    Text("Public address — advanced")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(NaruColors.coral)
                                        .accessibilityIdentifier(
                                            "naru.profile.row.publicWarning"
                                        )
                                }
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("Selected profile")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        isSelected
                            ? Color.accentColor.opacity(0.08)
                            : Color.clear
                    )
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

/// Leading status dot for a profile row.  Renders the most recent
/// diagnostic verdict from the app model's memory-only cache:
/// gray (no diagnostic ever run), green (every stage passed), amber
/// (passed with warnings — e.g. clipboard text path skipped), red
/// (some stage failed).  See `DiagnosticVerdict`.
private struct ProfileStatusDot: View {
    let verdict: DiagnosticVerdict

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        switch verdict {
        case .unknown:
            return .secondary.opacity(0.45)
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return NaruColors.coral
        }
    }

    private var accessibilityLabel: String {
        switch verdict {
        case .unknown:
            return "Status unknown"
        case .passed:
            return "Reachable"
        case .warning:
            return "Reachable with warnings"
        case .failed:
            return "Last attempt failed"
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
