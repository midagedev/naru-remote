import SwiftUI

public struct DiagnosticSummaryView: View {
    private let rows: [DiagnosticSummaryRow]

    public init(rows: [DiagnosticSummaryRow]) {
        self.rows = rows
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
        }
        .padding(16)
        .background(Color(red: 0.98, green: 0.98, blue: 0.96))
        .accessibilityIdentifier("naru.diagnostics.summary")
    }
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
