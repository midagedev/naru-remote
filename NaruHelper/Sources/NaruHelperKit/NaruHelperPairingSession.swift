import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import NaruRemoteCore

/// One **Pair with iPhone…** invocation (spec 041 FR-003): rotates the
/// pairing store, encodes the offer through the same
/// ``NaruPairingOfferWire`` the CLI uses, and renders it as a `CGImage`
/// QR. The CLI's `--pair` produces its URL through this type, so app and
/// terminal share one encoder path — the offer bytes for the same inputs
/// are identical by construction, not by coincidence.
///
/// The QR image is credential material: it lives only while a pairing
/// window is showing it, and ``end()`` drops it.
public final class NaruHelperPairingSession: @unchecked Sendable {
    private let lock = NSLock()

    /// Minimum rendered QR edge, in pixels — a phone camera reads this at
    /// arm's length (spec 041 FR-003).
    public static let minimumQRPixelSize = 320
    /// ISO/IEC 18004 quiet zone: four light modules on every side. The
    /// image bakes it in so any surface that displays the image unclipped
    /// stays scannable.
    public static let quietZoneModules = 4

    public let offerURL: String
    public let state: NaruHelperPairingState
    public private(set) var qrImage: CGImage?

    public static func begin(
        store: NaruHelperPairingStateStore,
        hostInfo: NaruHelperPairingHostInfo,
        vncPort: UInt16 = 5900,
        vncPassword: String? = nil
    ) throws -> NaruHelperPairingSession {
        let state = try store.rotate()
        let offer = NaruPairingOffer(
            host: .init(
                label: hostInfo.label,
                magicDns: hostInfo.magicDns,
                addresses: hostInfo.addresses,
                vncPort: vncPort
            ),
            helper: .init(
                token: state.token,
                fingerprint: state.fingerprint
            ),
            vncPassword: vncPassword
        )
        let url = try NaruPairingOfferWire.encode(offer)
        return NaruHelperPairingSession(
            state: state,
            offerURL: url,
            qrImage: makeQRImage(message: url)
        )
    }

    private init(
        state: NaruHelperPairingState,
        offerURL: String,
        qrImage: CGImage?
    ) {
        self.state = state
        self.offerURL = offerURL
        self.qrImage = qrImage
    }

    /// Dismiss path: drops the QR image. The token itself stays valid
    /// until the next rotation — a closed window does not revoke.
    public func end() {
        lock.withLock {
            qrImage = nil
        }
    }

    /// CoreImage `CIQRCodeGenerator` at correction level M (the level the
    /// terminal renderer and spec 040 chose), scaled nearest-neighbor so
    /// module edges stay crisp, with the quiet zone baked in.
    static func makeQRImage(message: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else {
            return nil
        }
        let moduleColumns = Int(output.extent.width)
        let moduleRows = Int(output.extent.height)
        guard moduleColumns > 0, moduleRows > 0 else {
            return nil
        }
        guard let moduleImage = CIContext().createCGImage(output, from: output.extent) else {
            return nil
        }

        let totalModules = max(moduleColumns, moduleRows) + quietZoneModules * 2
        let scale = max(1, Int((Double(minimumQRPixelSize) / Double(totalModules)).rounded(.up)))
        let pixels = totalModules * scale

        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.draw(
            moduleImage,
            in: CGRect(
                x: quietZoneModules * scale,
                y: quietZoneModules * scale,
                width: moduleColumns * scale,
                height: moduleRows * scale
            )
        )
        return context.makeImage()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
