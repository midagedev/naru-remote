import SwiftUI

/// First-launch home surface shown only while zero saved profiles
/// exist (spec FR-015).  One title, one primary action — entry into
/// the profile editor — and nothing else.  No checklist, no feature
/// preview, no Tailscale onboarding tour: capabilities become
/// discoverable when the user reaches them.
public struct EmptyHomeView: View {
    private let onAddProfile: () -> Void
    /// About & Feedback (spec 039 FR-002). The grid header carries the same
    /// entry, but the grid does not exist until a profile does — and a user
    /// who cannot get their first connection working is exactly the one who
    /// needs a way to say so.
    private let onAbout: (() -> Void)?

    public init(
        onAddProfile: @escaping () -> Void = {},
        onAbout: (() -> Void)? = nil
    ) {
        self.onAddProfile = onAddProfile
        self.onAbout = onAbout
    }

    public var body: some View {
        // UX (GRD-parity): the icon + heading + CTA used to sit at the
        // top with a large empty void below.  Wrap the block in leading
        // / trailing Spacers so it reads as a centered (slightly
        // above-center) group, and add a secondary subhead so the
        // first-launch screen explains what "a computer" means.
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                NaruMark()
                    .frame(width: 88, height: 88)

                VStack(spacing: 8) {
                    Text("Add a computer to begin.")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text("Connect to a Mac or Linux machine on your private network. Compose text on your phone — Naru sends the finished input across.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
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

            if let onAbout {
                Button(action: onAbout) {
                    Text("About & feedback")
                        .font(.footnote)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("naru.home.empty.about")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("naru.home.empty")
    }
}
