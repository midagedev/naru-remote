import NaruRemoteCore
import SwiftUI

public struct ConnectionGridView: View {
    private let cards: [ConnectionGridCard]
    private let onSelect: (ConnectionGridCard.ID) -> Void
    private let onAddProfile: () -> Void
    private let onDiagnostics: ((ConnectionGridCard.ID) -> Void)?
    private let onEdit: ((ConnectionGridCard.ID) -> Void)?
    private let onDelete: ((ConnectionGridCard.ID) -> Void)?
    @State private var pendingDeleteCard: ConnectionGridCard?

    public init(
        cards: [ConnectionGridCard],
        onSelect: @escaping (ConnectionGridCard.ID) -> Void,
        onAddProfile: @escaping () -> Void,
        onDiagnostics: ((ConnectionGridCard.ID) -> Void)? = nil,
        onEdit: ((ConnectionGridCard.ID) -> Void)? = nil,
        onDelete: ((ConnectionGridCard.ID) -> Void)? = nil
    ) {
        self.cards = cards
        self.onSelect = onSelect
        self.onAddProfile = onAddProfile
        self.onDiagnostics = onDiagnostics
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 220, maximum: 340),
                        spacing: 14,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(cards) { card in
                    ZStack(alignment: .topTrailing) {
                        ConnectionGridCardView(card: card) {
                            onSelect(card.id)
                        }

                        if onDiagnostics != nil || onEdit != nil || onDelete != nil {
                            profileActionsMenu(for: card)
                                .padding(8)
                        }
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("naru.connection.grid")
                    Text("Choose a saved computer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onAddProfile()
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .help("Add Profile")
                .accessibilityLabel("Add Profile")
                .accessibilityIdentifier("naru.connection.grid.add")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(NaruColors.canvas)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(NaruColors.hairline)
                    .frame(height: 1)
            }
        }
        .background(NaruColors.canvas)
        .alert(
            "Delete profile?",
            isPresented: Binding(
                get: { pendingDeleteCard != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteCard = nil
                    }
                }
            ),
            presenting: pendingDeleteCard
        ) { card in
            Button("Delete", role: .destructive) {
                pendingDeleteCard = nil
                onDelete?(card.id)
            }
            .accessibilityIdentifier("naru.connection.grid.delete.confirm")

            Button("Cancel", role: .cancel) {
                pendingDeleteCard = nil
            }
        } message: { card in
            Text("Remove \(card.displayName) and its saved credentials from this device?")
        }
    }

    nonisolated static func cardAccessibilityLabel(for card: ConnectionGridCard) -> String {
        let hostDescription: String
        switch card.hostKind {
        case .magicDNS:
            hostDescription = "MagicDNS address"
        case .privateAddress:
            hostDescription = "Private address"
        case .advancedManualPublicEndpoint:
            hostDescription = "Public address, advanced public endpoint warning"
        }

        var label = "\(card.displayName), \(card.endpoint), \(hostDescription), \(card.reachability.gridAccessibilityLabel), \(card.helperVideoReadiness.accessibilityLabel)"
        if let failure = card.failure {
            label += ", \(failure.message)"
        }
        return label
    }

    nonisolated static func cardAccessibilityHint(for card: ConnectionGridCard) -> String {
        switch card.hostKind {
        case .advancedManualPublicEndpoint:
            return "Review the public address and its security before connecting"
        case .magicDNS, .privateAddress:
            return "Connect to this saved computer"
        }
    }

    private func profileActionsMenu(for card: ConnectionGridCard) -> some View {
        Menu {
            if let onDiagnostics {
                Button {
                    onDiagnostics(card.id)
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
                .accessibilityIdentifier("naru.connection.grid.diagnostics")
            }

            if let onEdit {
                Button {
                    onEdit(card.id)
                } label: {
                    Label("Edit Profile", systemImage: "pencil")
                }
                .accessibilityIdentifier("naru.connection.grid.edit")
            }

            if onDelete != nil {
                Button(role: .destructive) {
                    pendingDeleteCard = card
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                }
                .accessibilityIdentifier("naru.connection.grid.delete")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Actions for \(card.displayName)")
        .accessibilityIdentifier("naru.connection.grid.actions")
    }
}

private struct ConnectionGridCardView: View {
    let card: ConnectionGridCard
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    preview

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(card.displayName)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 8)

                            statusBadge
                        }

                        // Host / MagicDNS / IP:port is a technical identifier —
                        // SF Mono per BRANDING.md §8 so it reads as an address,
                        // not prose, and digits/dots stay column-aligned.
                        Text(card.endpoint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if card.hostKind == .advancedManualPublicEndpoint {
                            Label("Public address", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(NaruColors.coral)
                                .lineLimit(1)
                                .accessibilityIdentifier("naru.connection.grid.publicWarning")
                        } else {
                            Label(card.hostKind.gridLabel, systemImage: card.hostKind.symbolName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Label(
                            card.helperVideoReadiness.label,
                            systemImage: card.helperVideoReadiness.symbolName
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(card.helperVideoReadiness.tint)
                        .lineLimit(1)
                        .accessibilityIdentifier("naru.connection.grid.helperVideo.\(card.helperVideoReadiness.identifier)")

                        if let failure = card.failure {
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(NaruColors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(ConnectionGridView.cardAccessibilityLabel(for: card))
            .accessibilityHint(ConnectionGridView.cardAccessibilityHint(for: card))
            .accessibilityIdentifier("naru.connection.grid.card")
            .accessibilityElement(children: .combine)
            // Combining children drops the button trait, and every UI test
            // (and VoiceOver) reaches this card through `app.buttons[...]`
            // — the same regression class as the 2026-07-12 dock finding.
            .accessibilityAddTraits(.isButton)

            if card.failure != nil {
                Button(action: onSelect) {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .accessibilityIdentifier("naru.connection.grid.reconnect")
            }
        }
        .background(NaruColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(NaruColors.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail = card.preview {
            ProfilePreviewThumbnailView(thumbnail: thumbnail)
        } else {
            previewPlaceholder
        }
    }

    private var previewPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(NaruColors.surfaceMuted)

            VStack(spacing: 8) {
                Image(systemName: card.hostKind.symbolName)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("No preview yet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("naru.connection.grid.preview.placeholder")
    }

    private var statusBadge: some View {
        Label(card.reachability.gridLabel, systemImage: card.reachability.symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(card.reachability.tint)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("naru.connection.grid.reachability.\(card.reachability.identifier)")
    }
}

private struct ProfilePreviewThumbnailView: View {
    let thumbnail: ProfilePreviewThumbnail

    var body: some View {
        ZStack {
            if let cgImage = thumbnail.cgImage {
                GeometryReader { proxy in
                    Image(decorative: cgImage, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                Rectangle()
                    .fill(NaruColors.surfaceMuted)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Last preview")
        .accessibilityIdentifier("naru.connection.grid.preview.thumbnail")
    }
}

private extension ConnectionGridHelperVideoReadiness {
    var identifier: String {
        switch status {
        case .vncOnly:
            return "vncOnly"
        case .checking:
            return "checking"
        case .ready:
            return "ready"
        case .needsSetup:
            return "needsSetup"
        case .needsPermission:
            return "needsPermission"
        case .disabled:
            return "disabled"
        case .revoked:
            return "revoked"
        case .blocked:
            return "blocked"
        case .vncFallback:
            return "vncFallback"
        }
    }

    var symbolName: String {
        switch status {
        case .vncOnly:
            return "display"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "video.fill"
        case .needsSetup:
            return "wrench.and.screwdriver.fill"
        case .needsPermission:
            return "lock.fill"
        case .disabled:
            return "video.slash.fill"
        case .revoked:
            return "xmark.shield.fill"
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .vncFallback:
            return "arrow.uturn.backward.circle.fill"
        }
    }

    var tint: Color {
        switch status {
        case .ready:
            return NaruColors.reachable
        case .checking, .needsSetup, .needsPermission, .vncFallback:
            return NaruColors.warning
        case .blocked, .revoked:
            return NaruColors.coral
        case .vncOnly, .disabled:
            return .secondary
        }
    }
}

private extension ProfileReachabilityState {
    var gridLabel: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking"
        case .reachable:
            return "Reachable"
        case .needsPassword:
            return "Password"
        case .unreachable:
            return "Unreachable"
        }
    }

    var gridAccessibilityLabel: String {
        switch self {
        case .unknown:
            return "reachability unknown"
        case .checking:
            return "checking reachability"
        case .reachable:
            return "reachable"
        case .needsPassword:
            return "reachable, needs VNC password"
        case .unreachable(let failedStage):
            return "unreachable at \(failedStage.rawValue)"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown:
            return "circle.dashed"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .reachable:
            return "checkmark.circle.fill"
        case .needsPassword:
            return "key.fill"
        case .unreachable:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unknown:
            return .secondary
        case .checking:
            return NaruColors.warning
        case .reachable:
            return NaruColors.reachable
        case .needsPassword:
            return NaruColors.warning
        case .unreachable:
            return NaruColors.coral
        }
    }

    var identifier: String {
        switch self {
        case .unknown:
            return "unknown"
        case .checking:
            return "checking"
        case .reachable:
            return "reachable"
        case .needsPassword:
            return "needsPassword"
        case .unreachable:
            return "unreachable"
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

    var gridLabel: String {
        switch self {
        case .magicDNS:
            return "MagicDNS"
        case .privateAddress:
            return "Private address"
        case .advancedManualPublicEndpoint:
            return "Advanced public endpoint"
        }
    }
}
