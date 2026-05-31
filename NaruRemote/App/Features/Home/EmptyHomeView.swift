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
        // UX (GRD-parity): the icon + heading + CTA used to sit at the
        // top with a large empty void below.  Wrap the block in leading
        // / trailing Spacers so it reads as a centered (slightly
        // above-center) group, and add a secondary subhead so the
        // first-launch screen explains what "a computer" means.
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Add a computer to begin.")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Connect to your Mac or Linux machine over your private Tailscale network.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: onAddProfile) {
                    Label("Add a Computer", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("naru.home.empty.addProfile")
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("naru.home.empty")
    }
}
