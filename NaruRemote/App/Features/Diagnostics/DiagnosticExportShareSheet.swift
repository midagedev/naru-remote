import SwiftUI

#if os(iOS) && canImport(UIKit)
import UIKit

/// Hosts a `UIActivityViewController` that lets the user attach the
/// safe-catalog diagnostic summary text to mail, Messages, or any
/// other share extension.  The activity items are intentionally a
/// single rendered `String` produced by
/// `DiagnosticExport.renderShareText(buildVersion:)` — this is the
/// only surface the shell uses to expose diagnostic content
/// externally (constitution §IV).
public struct DiagnosticExportShareSheet: UIViewControllerRepresentable {
    private let shareText: String

    public init(shareText: String) {
        self.shareText = shareText
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        // No-op: `UIActivityViewController` is configured at creation
        // time and the share text is captured by value, so there is
        // nothing to mutate on subsequent SwiftUI updates.
    }
}
#endif
