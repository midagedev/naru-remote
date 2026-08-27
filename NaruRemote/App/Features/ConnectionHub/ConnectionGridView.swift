import NaruRemoteCore
import SwiftUI

public struct ConnectionGridView: View {
    private let cards: [ConnectionGridCard]
    private let onSelect: (ConnectionGridCard.ID) -> Void
    private let onAddProfile: () -> Void
    private let onDiagnostics: ((ConnectionGridCard.ID) -> Void)?
    private let onEdit: ((ConnectionGridCard.ID) -> Void)?
    private let onDelete: ((ConnectionGridCard.ID) -> Void)?
    /// Connecting happens on this screen (spec 013 US-4), so cancelling it has
    /// to be reachable from the card that started it.
    private let onCancelConnection: (() -> Void)?
    /// Opens About & Feedback (spec 039 FR-002). Optional so existing call
    /// sites and previews that predate it keep compiling; the button hides
    /// when it is `nil`.
    private let onAbout: (() -> Void)?
    @State private var pendingDeleteCard: ConnectionGridCard?

    public init(
        cards: [ConnectionGridCard],
        onSelect: @escaping (ConnectionGridCard.ID) -> Void,
        onAddProfile: @escaping () -> Void,
        onDiagnostics: ((ConnectionGridCard.ID) -> Void)? = nil,
        onEdit: ((ConnectionGridCard.ID) -> Void)? = nil,
        onDelete: ((ConnectionGridCard.ID) -> Void)? = nil,
        onCancelConnection: (() -> Void)? = nil,
        onAbout: (() -> Void)? = nil
    ) {
        self.cards = cards
        self.onSelect = onSelect
        self.onAddProfile = onAddProfile
        self.onDiagnostics = onDiagnostics
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onCancelConnection = onCancelConnection
        self.onAbout = onAbout
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
                        ConnectionGridCardView(
                            card: card,
                            onSelect: { onSelect(card.id) },
                            onCancelConnection: onCancelConnection
                        )

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

                if let onAbout {
                    // Quiet, and to the left of the one primary action: this
                    // is where a user goes to report something, not something
                    // they do every session (spec 039 FR-002).
                    Button(action: onAbout) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .frame(width: 22, height: 22)
                            // Visual weight stays small; the hit target does
                            // not (the 44pt rule this header already applies
                            // to the card `⋯` menu).
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NaruColors.mutedInk)
                    .help("About Naru Remote")
                    .accessibilityLabel("About Naru Remote")
                    .accessibilityIdentifier("naru.connection.grid.about")
                }

                Button {
                    onAddProfile()
                } label: {
                    // The screen's one primary action — Signal Blue per the
                    // BRANDING.md §7 usage rule (spec 016 FR-004); a gray
                    // capsule read as a disabled control.
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
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
        if let connecting = card.connecting {
            label += ", \(connecting.label)"
        }
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
            // Opaque key chrome, not a translucent material: the button sits
            // over preview pixels, and a material's contrast is decided by
            // whatever desktop the thumbnail happens to show — the same class
            // BRANDING.md §7 bans for remote-screen chrome (spec 016 FR-003).
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(NaruColors.surfaceKey, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
                // Visual weight shrinks; the hit target keeps its 44pt.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Actions for \(card.displayName)")
        .accessibilityIdentifier("naru.connection.grid.actions")
    }
}

private struct ConnectionGridCardView: View {
    let card: ConnectionGridCard
    let onSelect: () -> Void
    let onCancelConnection: (() -> Void)?

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

                        // One tag row instead of a stacked caption list (spec
                        // 016 FR-001): the card reads name → address → traits,
                        // not a debug listing.
                        HStack(spacing: 6) {
                            if card.hostKind == .advancedManualPublicEndpoint {
                                metadataTag(
                                    "Public address",
                                    systemImage: "exclamationmark.triangle.fill",
                                    iconTint: NaruColors.coral
                                )
                                .accessibilityIdentifier("naru.connection.grid.publicWarning")
                            } else {
                                metadataTag(
                                    card.hostKind.gridLabel,
                                    systemImage: card.hostKind.symbolName
                                )
                            }

                            metadataTag(
                                card.helperVideoReadiness.label,
                                systemImage: card.helperVideoReadiness.symbolName,
                                iconTint: card.helperVideoReadiness.tint
                            )
                            .accessibilityIdentifier("naru.connection.grid.helperVideo.\(card.helperVideoReadiness.identifier)")
                        }

                        if let connecting = card.connecting {
                            // The progress lives on the card instead of on a
                            // screen of its own: remote control opens when
                            // there is a remote screen to show (spec 013 US-4).
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(connecting.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("naru.connection.grid.connecting")
                        } else if let failure = card.failure {
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

            if card.connecting != nil, let onCancelConnection {
                Button(role: .cancel, action: onCancelConnection) {
                    Text("Cancel")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .accessibilityIdentifier("naru.connection.grid.cancel")
            } else if card.failure != nil {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(NaruColors.hairline, lineWidth: 1)
        }
        // Quiet elevation (spec 016 FR-003): enough for the card to sit on
        // the canvas instead of being a ruled box, low enough to stay matte.
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    /// Compact capsule tag for card traits (spec 016 FR-001). Text stays
    /// neutral ink for AA; a status hue rides only on the icon (3:1 non-text).
    private func metadataTag(
        _ text: String,
        systemImage: String,
        iconTint: Color = .secondary
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(iconTint)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(NaruColors.surfaceMuted, in: Capsule())
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

            VStack(spacing: 6) {
                Image(systemName: card.hostKind.symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text("No preview yet")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("naru.connection.grid.preview.placeholder")
    }

    /// Status = colored dot + neutral text in a quiet capsule (spec 016
    /// FR-002). Colored *text* on a light surface is where AA quietly dies
    /// (Link Green on Surface is ~2.9:1); a dot needs only the 3:1 non-text
    /// contrast and the words stay ink.
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(card.reachability.tint)
                .frame(width: 7, height: 7)
            Text(card.reachability.gridLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(NaruColors.surfaceMuted, in: Capsule())
        .overlay(Capsule().stroke(NaruColors.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.reachability.gridAccessibilityLabel)
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
                        // The thumbnail now arrives larger than the card
                        // (spec 038 FR-011), so what happens here is a
                        // downscale — where `.high` is worth its cost and
                        // `.medium` was leaving stair-stepping on desktop text.
                        .interpolation(.high)
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
