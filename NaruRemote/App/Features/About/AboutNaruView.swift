import SwiftUI

/// About & Feedback (spec 039 FR-002).
///
/// The app had no surface of this kind at all: no version, no way to reach the
/// person who wrote it, no acknowledgement of the one package it depends on,
/// and no answer to "what does this thing send anywhere". A remote-control app
/// asking for a password and a private-network address has to answer that last
/// one somewhere the user can find without taking anybody's word for it.
///
/// Every destination is a plain `Link`. Nothing here collects anything.
public struct AboutNaruView: View {
    @Environment(\.dismiss) private var dismiss

    private let buildVersion: String?
    private let bundleBuild: String?

    public init(buildVersion: String? = nil, bundleBuild: String? = nil) {
        self.buildVersion = buildVersion
        self.bundleBuild = bundleBuild ?? Self.bundleBuildNumber()
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    Link(destination: Self.newBugReportURL) {
                        Label("Report a problem", systemImage: "ladybug")
                    }
                    .accessibilityIdentifier("naru.about.reportIssue")

                    Link(destination: Self.newFeatureRequestURL) {
                        Label("Suggest a feature", systemImage: "lightbulb")
                    }
                    .accessibilityIdentifier("naru.about.requestFeature")
                } header: {
                    Text("Feedback")
                } footer: {
                    // The diagnostic export is already built to be safe to
                    // paste in public (constitution §IV — fixed catalog, no
                    // addresses, no composed text). Saying so is what makes a
                    // bug report reproducible instead of a description of a
                    // feeling.
                    Text("A connection that misbehaves has a story to tell: open **Session tools → Diagnostics**, tap Share, and paste it into the report. The export carries stage results only — no addresses, passwords, or anything you typed.")
                }

                Section("Project") {
                    Link(destination: Self.repositoryURL) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .accessibilityIdentifier("naru.about.source")

                    Link(destination: Self.authorURL) {
                        Label("@midagedev on X", systemImage: "at")
                    }
                    .accessibilityIdentifier("naru.about.author")
                }

                Section("What leaves this device") {
                    fact(
                        "Your Mac, and nothing else.",
                        detail: "Naru Remote talks to the computer you name and to no server of ours. There is no account, no telemetry, and no analytics."
                    )
                    fact(
                        "Passwords stay in the Keychain.",
                        detail: "A saved VNC password is written to this device's Keychain and referenced by name. It is never stored in the profile file and never leaves the device except to the server you are connecting to."
                    )
                    fact(
                        "Logs keep counts, not content.",
                        detail: "Diagnostics record which stage passed or failed. Text you compose, screen contents, and addresses are not written to them."
                    )
                }

                Section("Built with") {
                    Link(destination: Self.glasskeysURL) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("glasskeys")
                                .font(.body.weight(.medium))
                            Text("Sticky modifiers, hold-to-repeat, and the composition gate — written here, then shared.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("naru.about.glasskeys")
                }

                Section {
                    Text("MIT licensed. © 2026 Hyeoncheol Kim.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Naru Remote is not affiliated with or endorsed by Tailscale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("naru.about.done")
                }
            }
        }
        .accessibilityIdentifier("naru.about")
    }

    private var header: some View {
        VStack(spacing: 12) {
            NaruMark()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("Naru Remote")
                    .font(.title3.weight(.semibold))
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("naru.about.version")
            }

            Text("Compose on the phone. Send finished input to the computer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 12)
    }

    private func fact(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// "Version 1.0.0 (12)", or "Version — " when neither key is readable,
    /// which is what previews and unit tests see.
    var versionLine: String {
        switch (buildVersion, bundleBuild) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        default:
            return "Version —"
        }
    }

    private static func bundleBuildNumber() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    // MARK: - Destinations

    /// Force-unwrapped on purpose: these are compile-time literals, and a
    /// silently-nil optional would render a row that does nothing when tapped.
    /// A malformed literal here fails on the first launch of any build, which
    /// is exactly when it should.
    static let repositoryURL = URL(string: "https://github.com/midagedev/naru-remote")!
    static let newBugReportURL = URL(
        string: "https://github.com/midagedev/naru-remote/issues/new?template=bug_report.yml"
    )!
    static let newFeatureRequestURL = URL(
        string: "https://github.com/midagedev/naru-remote/issues/new?template=feature_request.yml"
    )!
    static let authorURL = URL(string: "https://x.com/midagedev")!
    static let glasskeysURL = URL(string: "https://github.com/midagedev/glasskeys")!
}

#Preview {
    AboutNaruView(buildVersion: "1.0.0", bundleBuild: "12")
}
