import NaruRemoteCore
import SwiftUI

public struct OnboardingGuideView: View {
    private let guide: OnboardingGuide
    private let onDismiss: () -> Void

    public init(
        guide: OnboardingGuide,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.guide = guide
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("First Run", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                if let nextStep = guide.firstActionableStep {
                    Text(nextStep.actionTitle ?? nextStep.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide first run checklist")
                .accessibilityLabel("Hide first run checklist")
                .accessibilityIdentifier("naru.onboarding.dismiss")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(guide.steps) { step in
                    GridRow {
                        Image(systemName: step.state.symbolName)
                            .foregroundStyle(step.state.tint)
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(step.state.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(step.state.tint)
                            .frame(minWidth: 62, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.94, green: 0.96, blue: 0.94))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("naru.onboarding.guide")
    }
}

private extension OnboardingStepState {
    var symbolName: String {
        switch self {
        case .complete:
            return "checkmark.circle.fill"
        case .next:
            return "arrow.right.circle.fill"
        case .waiting:
            return "clock.fill"
        case .blocked:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .complete:
            return .green
        case .next:
            return .teal
        case .waiting:
            return .secondary
        case .blocked:
            return .orange
        }
    }

    var label: String {
        switch self {
        case .complete:
            return "Done"
        case .next:
            return "Next"
        case .waiting:
            return "Waiting"
        case .blocked:
            return "Check"
        }
    }
}
