import NaruRemoteCore
import SwiftUI

public struct OnboardingGuideView: View {
    private let guide: OnboardingGuide
    private let isCompact: Bool
    private let onDismiss: () -> Void
    private let onAction: (OnboardingStepID) -> Void
    private let onExpandFromCompact: () -> Void

    @State private var userExpandedFromCompact = false

    public init(
        guide: OnboardingGuide,
        isCompact: Bool = false,
        onDismiss: @escaping () -> Void = {},
        onAction: @escaping (OnboardingStepID) -> Void = { _ in },
        onExpandFromCompact: @escaping () -> Void = {}
    ) {
        self.guide = guide
        self.isCompact = isCompact
        self.onDismiss = onDismiss
        self.onAction = onAction
        self.onExpandFromCompact = onExpandFromCompact
    }

    public var body: some View {
        Group {
            // When the iOS keyboard is up (compose focus) we render
            // a 1-line summary banner — closes UX punch-list #009.
            // The user can tap to temporarily expand the checklist
            // back to full height, but the default while the
            // keyboard is presented is the compact summary.
            if isCompact && !userExpandedFromCompact {
                compactBanner
            } else {
                fullChecklist
            }
        }
        .animation(.default, value: isCompact)
        .animation(.default, value: userExpandedFromCompact)
        .accessibilityIdentifier("naru.onboarding.guide")
    }

    /// Full checklist body — first-run hero panel that lists every
    /// onboarding step and lets the user dismiss the panel.
    private var fullChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("First Run", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                if let nextStep = guide.firstActionableStep {
                    // Read-only "next-step" label.  The tappable
                    // CTA pill that used to live next to this label
                    // was removed — closes UX punch-list #101 (the
                    // toolbar's "Add Profile" is the durable home
                    // for the action; this label is a status hint).
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

            // Closes UX punch-list #105 — empty-state caption that
            // names Tailscale as an external dependency without
            // implying Naru is officially affiliated (constitution
            // §II).  Only shown when no profile has been added yet,
            // which is the moment the user might be looking for
            // setup instructions.
            if guide.firstActionableStep?.id == .privateTarget {
                Text("Naru does not configure Tailscale — set up your tailnet first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("naru.onboarding.tailscale.caption")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(guide.steps) { step in
                    stepRow(step)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: guide.steps.map(\.state))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NaruColors.dock)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// Per-step row.  Three visual heights — full for the active /
    /// blocked step, intermediate for waiting, compact ("✓ <title>
    /// — Done") for completed.  Closes UX punch-list #202.
    @ViewBuilder
    private func stepRow(_ step: OnboardingStep) -> some View {
        let isActive = guide.firstActionableStep?.id == step.id
        switch step.state {
        case .complete:
            compactDoneRow(step)
        case .next, .blocked:
            fullRow(step, isActive: isActive)
        case .waiting:
            waitingRow(step)
        }
    }

    /// 24pt-ish single-line "Done" row.  Renders only the
    /// checkmark + title, no detail copy, no trailing label.
    private func compactDoneRow(_ step: OnboardingStep) -> some View {
        HStack(spacing: 8) {
            Image(systemName: step.state.symbolName)
                .foregroundStyle(step.state.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text("\(step.title) — Done")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
        .padding(.vertical, 2)
    }

    /// Full-height active / blocked row — semibold title + accent
    /// background tint.  Closes UX punch-list #106.
    private func fullRow(_ step: OnboardingStep, isActive: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: step.state.symbolName)
                .foregroundStyle(step.state.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(step.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(step.state.tint)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive
                ? Color.accentColor.opacity(0.06)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Intermediate "waiting" row — visible but de-emphasised.
    /// Single-line detail, secondary foreground throughout.
    private func waitingRow(_ step: OnboardingStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: step.state.symbolName)
                .foregroundStyle(step.state.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(step.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(step.state.tint)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .frame(minHeight: 32)
        .padding(.vertical, 2)
    }

    /// 1-line keyboard-presented summary — closes UX punch-list
    /// #009.  Tap anywhere on the banner to expand the checklist
    /// back to full height.
    private var compactBanner: some View {
        let doneCount = guide.steps.filter { $0.state == .complete }.count
        let total = guide.steps.count
        let activeTitle = guide.firstActionableStep?.title ?? "Almost done"

        return Button {
            userExpandedFromCompact = true
            onExpandFromCompact()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("First Run · \(doneCount) of \(total) done — \(activeTitle)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NaruColors.dock)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("First Run checklist, \(doneCount) of \(total) done. Tap to expand.")
        .accessibilityIdentifier("naru.onboarding.guide.compact")
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
            return .accentColor
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
