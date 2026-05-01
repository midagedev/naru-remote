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
public protocol LocalClipboardWriting: AnyObject, Sendable {
    func write(_ text: String)
}

#if canImport(UIKit) && os(iOS)
/// Default `LocalClipboardWriting` that puts the accepted text on
/// `UIPasteboard.general`.  Constructed by the iOS app target and
/// injected into `NaruRemoteAppModel`.
public final class UIPasteboardClipboardWriter: LocalClipboardWriting, @unchecked Sendable {
    public init() {}

    public func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}
#endif
