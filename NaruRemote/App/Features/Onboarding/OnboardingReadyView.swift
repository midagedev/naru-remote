import SwiftUI

/// Compact affirmation surface shown once every step in the
/// first-run `OnboardingGuide` reaches `.complete` but the user has
/// not yet dismissed the checklist persistence flag.  Watch-only:
/// the view never displays composed draft contents, credential
/// refs, or framebuffer data (constitution §IV).
///
/// Tapping "Got it" routes through the same
/// `dismissOnboardingChecklist()` path the in-progress
/// `OnboardingGuideView` uses, so the dismissal persists across
/// launches just like the in-progress checklist's xmark button
/// (see PR #8).
public struct OnboardingReadyView: View {
    private let onDismiss: () -> Void

    public init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("You're all set. Naru Remote is ready.")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Got it") {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.green)
            .accessibilityIdentifier("naru.onboarding.ready.dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.96, blue: 0.94))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("naru.onboarding.ready")
    }
}
