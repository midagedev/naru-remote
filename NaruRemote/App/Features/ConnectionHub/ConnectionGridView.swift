import NaruRemoteCore
import SwiftUI

public struct ConnectionGridView: View {
    private let cards: [ConnectionGridCard]
    private let onSelect: (ConnectionGridCard.ID) -> Void
    private let onAddProfile: () -> Void

    public init(
        cards: [ConnectionGridCard],
        onSelect: @escaping (ConnectionGridCard.ID) -> Void,
        onAddProfile: @escaping () -> Void
    ) {
        self.cards = cards
        self.onSelect = onSelect
        self.onAddProfile = onAddProfile
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
                    Button {
                        onSelect(card.id)
                    } label: {
                        ConnectionGridCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("naru.connection.grid.card")
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connections")
                        .font(.title2.weight(.semibold))
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
        .accessibilityIdentifier("naru.connection.grid")
    }
}

private struct ConnectionGridCardView: View {
    let card: ConnectionGridCard

    var body: some View {
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

                Text(card.endpoint)
                    .font(.caption)
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
            }
            .padding(12)
        }
        .background(NaruColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    card.isSelected ? NaruColors.focusRing : NaruColors.hairline,
                    lineWidth: card.isSelected ? 2 : 1
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.displayName), \(card.endpoint), \(card.verdict.gridAccessibilityLabel)")
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
        Label(card.verdict.gridLabel, systemImage: card.verdict.symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(card.verdict.tint)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("naru.connection.grid.status.\(card.verdict.rawValue)")
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

private extension DiagnosticVerdict {
    var gridLabel: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .passed:
            return "Reachable"
        case .warning:
            return "Check"
        case .failed:
            return "Issue"
        }
    }

    var gridAccessibilityLabel: String {
        switch self {
        case .unknown:
            return "reachability unknown"
        case .passed:
            return "reachable"
        case .warning:
            return "reachable with warnings"
        case .failed:
            return "last check failed"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown:
            return "circle.dashed"
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unknown:
            return .secondary
        case .passed:
            return NaruColors.reachable
        case .warning:
            return NaruColors.warning
        case .failed:
            return NaruColors.coral
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
