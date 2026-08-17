import NaruRemoteCore
import SwiftUI

/// A privacy-safe, render-ready summary for the persistent Operation
/// diagnostic affordance. Only the typed session state, coarse connection
/// quality, and fixed-catalog diagnostic rows contribute to this value.
/// `RemoteSession.hudMessage` and `lastError` are deliberately ignored.
public struct SessionDiagnosticCornerState: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case neutral
        case progress
        case healthy
        case warning
        case critical
    }

    public let primaryText: String
    public let secondaryText: String?
    public let systemImage: String
    public let tone: Tone
    public let accessibilityValue: String
    public let rows: [DiagnosticSummaryRow]

    public init(
        session: RemoteSession?,
        connectionQuality: ConnectionQuality,
        rows: [DiagnosticSummaryRow]
    ) {
        self.rows = rows

        let latestFailure = rows.last { $0.status == "failed" }
        let presentation = Self.presentation(
            for: session?.state,
            connectionQuality: connectionQuality,
            latestFailure: latestFailure
        )

        primaryText = presentation.primaryText
        secondaryText = presentation.secondaryText
        systemImage = presentation.systemImage
        tone = presentation.tone
        accessibilityValue = presentation.accessibilityValue
    }

    private static func presentation(
        for state: RemoteSessionState?,
        connectionQuality: ConnectionQuality,
        latestFailure: DiagnosticSummaryRow?
    ) -> Presentation {
        switch state {
        case nil:
            return Presentation(
                primaryText: "Not connected",
                secondaryText: latestFailure.map { "Last: \($0.title)" },
                systemImage: "circle.dashed",
                tone: .neutral,
                accessibilityValue: accessibilityValue(
                    "Not connected",
                    latestFailure: latestFailure
                )
            )

        case .connecting:
            return Presentation(
                primaryText: "Connecting",
                secondaryText: nil,
                systemImage: "arrow.triangle.2.circlepath",
                tone: .progress,
                accessibilityValue: "Connecting"
            )

        case .authenticating:
            return Presentation(
                primaryText: "Authenticating",
                secondaryText: nil,
                systemImage: "lock.shield",
                tone: .progress,
                accessibilityValue: "Authenticating"
            )

        case .active:
            return activePresentation(connectionQuality: connectionQuality)

        case let .reconnecting(attempt, total):
            let safeTotal = max(total, 1)
            let safeAttempt = min(max(attempt, 1), safeTotal)
            return Presentation(
                primaryText: "Reconnecting",
                secondaryText: "\(safeAttempt)/\(safeTotal)",
                systemImage: "arrow.clockwise",
                tone: .warning,
                accessibilityValue: "Reconnecting, attempt \(safeAttempt) of \(safeTotal)"
            )

        case .degraded:
            let secondary = latestFailure?.title ?? qualityText(connectionQuality) ?? "Limited"
            return Presentation(
                primaryText: "Degraded",
                secondaryText: secondary,
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                accessibilityValue: accessibilityValue(
                    "Connection degraded",
                    fallbackDetail: secondary,
                    latestFailure: latestFailure
                )
            )

        case .failed:
            return Presentation(
                primaryText: "Failed",
                secondaryText: latestFailure?.title,
                systemImage: "xmark.octagon.fill",
                tone: .critical,
                accessibilityValue: accessibilityValue(
                    "Connection failed",
                    latestFailure: latestFailure
                )
            )

        case .closed:
            return Presentation(
                primaryText: "Disconnected",
                secondaryText: latestFailure.map { "Last: \($0.title)" },
                systemImage: "rectangle.portrait.and.arrow.right",
                tone: .neutral,
                accessibilityValue: accessibilityValue(
                    "Disconnected",
                    latestFailure: latestFailure
                )
            )
        }
    }

    private static func activePresentation(
        connectionQuality: ConnectionQuality
    ) -> Presentation {
        switch connectionQuality {
        case .unknown:
            return Presentation(
                primaryText: "Connected",
                secondaryText: "Measuring",
                systemImage: "checkmark.circle",
                tone: .progress,
                accessibilityValue: "Connected, connection quality not measured yet"
            )
        case .good:
            return Presentation(
                primaryText: "Connected",
                secondaryText: "Good",
                systemImage: "checkmark.circle.fill",
                tone: .healthy,
                accessibilityValue: "Connected, connection quality good"
            )
        case .fair:
            return Presentation(
                primaryText: "Connected",
                secondaryText: "Fair",
                systemImage: "exclamationmark.circle.fill",
                tone: .warning,
                accessibilityValue: "Connected, connection quality fair"
            )
        case .poor:
            return Presentation(
                primaryText: "Connected",
                secondaryText: "Poor",
                systemImage: "exclamationmark.triangle.fill",
                tone: .critical,
                accessibilityValue: "Connected, connection quality poor"
            )
        }
    }

    private static func qualityText(_ quality: ConnectionQuality) -> String? {
        switch quality {
        case .unknown: return nil
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    private static func accessibilityValue(
        _ status: String,
        fallbackDetail: String? = nil,
        latestFailure: DiagnosticSummaryRow?
    ) -> String {
        if let latestFailure {
            return "\(status), \(latestFailure.title), \(latestFailure.detail)"
        }
        if let fallbackDetail {
            return "\(status), \(fallbackDetail)"
        }
        return status
    }

    private struct Presentation {
        let primaryText: String
        let secondaryText: String?
        let systemImage: String
        let tone: Tone
        let accessibilityValue: String
    }
}

/// Persistent Operation-corner affordance. It occupies a compact 44-point
/// target over the viewport and moves the full safe diagnostic collection to
/// a medium/large sheet, so diagnostics stay discoverable without creating a
/// third primary screen or permanently reducing the remote canvas.
public struct SessionDiagnosticCornerView: View {
    nonisolated static let minimumHitDimension: CGFloat = 44
    nonisolated static let maximumCompactWidth: CGFloat = 248

    private let state: SessionDiagnosticCornerState
    private let shareTextProvider: (() -> String)?
    private let externalDetailPresentation: Binding<Bool>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isLocallyPresentingDetail = false

    public init(
        session: RemoteSession?,
        connectionQuality: ConnectionQuality,
        rows: [DiagnosticSummaryRow],
        isDetailPresented: Binding<Bool>? = nil,
        shareTextProvider: (() -> String)? = nil
    ) {
        self.init(
            state: SessionDiagnosticCornerState(
                session: session,
                connectionQuality: connectionQuality,
                rows: rows
            ),
            isDetailPresented: isDetailPresented,
            shareTextProvider: shareTextProvider
        )
    }

    public init(
        state: SessionDiagnosticCornerState,
        isDetailPresented: Binding<Bool>? = nil,
        shareTextProvider: (() -> String)? = nil
    ) {
        self.state = state
        self.externalDetailPresentation = isDetailPresented
        self.shareTextProvider = shareTextProvider
    }

    public var body: some View {
        Button {
            detailPresentation.wrappedValue = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state.systemImage)
                    .foregroundStyle(toneColor)

                Text(state.primaryText)
                    .fontWeight(.semibold)

                if let secondaryText = state.secondaryText {
                    Text("·")
                        .foregroundStyle(NaruColors.mutedInk)
                    Text(secondaryText)
                        .foregroundStyle(NaruColors.mutedInk)
                }

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(NaruColors.mutedInk)
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 12)
            .frame(minHeight: Self.minimumHitDimension)
            .frame(maxWidth: Self.maximumCompactWidth)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NaruColors.ink)
        .background { capsuleBackground }
        .overlay {
            Capsule()
                .strokeBorder(toneColor.opacity(0.38), lineWidth: 1)
        }
        .accessibilityLabel("Diagnostics")
        .accessibilityValue(state.accessibilityValue)
        .accessibilityHint("Shows connection diagnostics")
        .accessibilityIdentifier("naru.session.diagnostics.corner")
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .sheet(isPresented: detailPresentation) {
            SessionDiagnosticDetailSheet(
                rows: state.rows,
                shareTextProvider: shareTextProvider
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var detailPresentation: Binding<Bool> {
        Binding(
            get: {
                externalDetailPresentation?.wrappedValue
                    ?? isLocallyPresentingDetail
            },
            set: { isPresented in
                if let externalDetailPresentation {
                    externalDetailPresentation.wrappedValue = isPresented
                } else {
                    isLocallyPresentingDetail = isPresented
                }
            }
        )
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        if reduceTransparency {
            Capsule().fill(NaruColors.surface)
        } else {
            Capsule().fill(.regularMaterial)
        }
    }

    private var toneColor: Color {
        switch state.tone {
        case .neutral: return NaruColors.mutedInk
        case .progress: return NaruColors.signalBlue
        case .healthy: return NaruColors.reachable
        case .warning: return NaruColors.warning
        case .critical: return NaruColors.coral
        }
    }
}

/// Shared by the session capsule and the host-card Diagnostics menu
/// item (spec 013 US2-1); internal so both call sites render one sheet.
struct SessionDiagnosticDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let rows: [DiagnosticSummaryRow]
    let shareTextProvider: (() -> String)?

    var body: some View {
        NavigationStack {
            #if os(iOS)
            content.navigationBarTitleDisplayMode(.inline)
            #else
            content
            #endif
        }
    }

    private var content: some View {
        ScrollView {
            DiagnosticSummaryView(
                rows: rows,
                shareTextProvider: shareTextProvider,
                showsHeader: false
            )
            .padding()
        }
        .background(NaruColors.canvas)
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
