import SwiftUI

/// First-launch home surface shown only while zero saved profiles
/// exist (spec FR-015).  One title, one primary action — entry into
/// the profile editor — and nothing else.  No checklist, no feature
/// preview, no Tailscale onboarding tour: capabilities become
/// discoverable when the user reaches them.
public struct EmptyHomeView: View {
    private let onAddProfile: () -> Void

    public init(onAddProfile: @escaping () -> Void = {}) {
        self.onAddProfile = onAddProfile
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Add a computer to begin.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Button(action: onAddProfile) {
                Label("Add a Computer", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("naru.home.empty.addProfile")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 64)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("naru.home.empty")
    }
}
