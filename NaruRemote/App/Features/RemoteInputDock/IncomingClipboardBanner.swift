import Foundation
import SwiftUI

/// Pending review of a `ServerCutText` payload that arrived from the
/// remote computer.  The full `text` is never shown in the banner —
/// only `previewText` is rendered — so that screenshotting the iPad
/// while a remote-copy banner is visible cannot leak more than ~80
/// characters of context.  The full `text` becomes accessible only
/// after the user taps **Accept**, at which point
/// `NaruRemoteAppModel` writes it through `LocalClipboardWriting`.
public struct IncomingClipboardReview: Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let previewText: String
    public let arrivedAt: Date

    /// Soft cap on how many characters of the remote-copied text are
    /// rendered in the banner.  Picked to fit two lines on a compact
    /// iPhone width without spilling the layout.
    public static let previewCharacterLimit = 80

    public init(text: String, arrivedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.arrivedAt = arrivedAt
        self.previewText = Self.truncate(text, limit: Self.previewCharacterLimit)
    }

    static func truncate(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        if collapsed.count <= limit {
            return collapsed
        }
        let prefix = collapsed.prefix(limit)
        return "\(prefix)\u{2026}"
    }
}

/// SwiftUI banner that asks the user whether to accept a remote-copied
/// text payload onto the local pasteboard.  Renders nothing when
/// `review` is `nil`, so it is safe to keep wired into the bottom safe
/// area inset of the detail view at all times.
public struct IncomingClipboardBanner: View {
    private let review: IncomingClipboardReview?
    private let onAccept: () -> Void
    private let onDismiss: () -> Void

    public init(
        review: IncomingClipboardReview?,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.review = review
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if let review {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.subheadline)
                    Text("Remote clipboard ready")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("from remote")
                        .font(.caption)
                        .foregroundStyle(NaruColors.mutedInk)
                }
                .foregroundStyle(NaruColors.ink)

                Text(review.previewText)
                    .font(.callout)
                    .foregroundStyle(NaruColors.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("naru.input.incomingClipboard.preview")

                HStack(spacing: 12) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("naru.input.incomingClipboard.dismiss")

                    Spacer()

                    Button {
                        onAccept()
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("naru.input.incomingClipboard.accept")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(NaruColors.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NaruColors.hairline)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("naru.input.incomingClipboard.banner")
            .accessibilityElement(children: .contain)
        }
    }
}
