import SwiftUI

public struct DiagnosticSummaryView: View {
    private let rows: [DiagnosticSummaryRow]
    /// Closure that produces the safe diagnostic share payload on demand.
    /// The shell wires this to
    /// `model.makeDiagnosticExport().renderSharePayload(buildVersion:)`
    /// so the view never reaches into `DiagnosticExport` directly.
    /// `nil` hides the Share Diagnostics affordance entirely
    /// (constitution §IV: prefer absence over a stub that could leak).
    private let shareTextProvider: (() -> String)?
    @State private var shareText: String?

    public init(
        rows: [DiagnosticSummaryRow],
        shareTextProvider: (() -> String)? = nil
    ) {
        self.rows = rows
        self.shareTextProvider = shareTextProvider
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
            }

            if rows.isEmpty {
                Text("No diagnostics yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.status.symbolName)
                            .foregroundStyle(row.status.tint)
                            .frame(width: 20)
                            .help(row.status)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.callout.weight(.medium))
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(row.stage)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let shareTextProvider {
                HStack {
                    Spacer()
                    Button {
                        shareText = shareTextProvider()
                    } label: {
                        Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("naru.diagnostics.share")
                    .disabled(rows.isEmpty)
                }
            }
        }
        .padding(16)
        .background(NaruColors.surface)
        .accessibilityIdentifier("naru.diagnostics.summary")
        #if os(iOS) && canImport(UIKit)
        .sheet(item: Binding(
            get: { shareText.map(DiagnosticShareText.init) },
            set: { newValue in shareText = newValue?.text }
        )) { payload in
            DiagnosticExportShareSheet(shareText: payload.text)
        }
        #endif
    }
}

/// `Identifiable` wrapper used as the `sheet(item:)` payload.  The
/// rendered share text is the identifier — tapping the button twice
/// in a row produces a different timestamp and therefore a different
/// id, which forces SwiftUI to re-present a fresh activity sheet.
private struct DiagnosticShareText: Identifiable {
    let text: String
    var id: String { text }
}

private extension String {
    var symbolName: String {
        switch self {
        case "passed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.octagon.fill"
        case "running":
            return "arrow.triangle.2.circlepath"
        case "skipped":
            return "minus.circle"
        default:
            return "circle"
        }
    }

    var tint: Color {
        switch self {
        case "passed":
            return .green
        case "failed":
            return .red
        case "running":
            return .blue
        case "skipped":
            return .secondary
        default:
            return .secondary
        }
    }
}
