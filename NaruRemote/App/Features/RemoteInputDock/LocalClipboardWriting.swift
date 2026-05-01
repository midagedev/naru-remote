#if canImport(UIKit)
import UIKit
#endif

/// Boundary that lets `NaruRemoteAppModel` write text to the local
/// device pasteboard without a hard `UIPasteboard` dependency.  Tests
/// substitute an in-memory recorder so unit tests never touch
/// `UIPasteboard.general`.
///
/// This is the *OUT* direction of constitution §I "Input Composed
/// Locally": text travels from the remote server to the local
/// pasteboard only after the user has reviewed the preview and tapped
/// Accept in `IncomingClipboardBanner`.  It is intentionally not
/// auto-paste into the Compose & Send draft.
///
/// `write(_:)` is `@MainActor` because the only production conformer
/// (`UIPasteboardClipboardWriter`) writes to `UIPasteboard.general`,
/// which is a UIKit surface, and the only caller is
/// `NaruRemoteAppModel.acceptIncomingClipboard()` — itself
/// `@MainActor`.  Encoding that isolation in the protocol lets
/// conformers be plain `Sendable`-by-isolation types and avoids
/// `@unchecked Sendable`.
public protocol LocalClipboardWriting: AnyObject, Sendable {
    @MainActor func write(_ text: String)
}

#if canImport(UIKit) && os(iOS)
/// Default `LocalClipboardWriting` that puts the accepted text on
/// `UIPasteboard.general`.  Constructed by the iOS app target and
/// injected into `NaruRemoteAppModel`.
@MainActor
public final class UIPasteboardClipboardWriter: LocalClipboardWriting {
    public init() {}

    public func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}
#endif
