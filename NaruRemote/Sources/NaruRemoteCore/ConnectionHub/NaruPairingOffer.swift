import CryptoKit
import Foundation

/// Pure, SwiftUI-free wire format for QR pairing (spec 040).
///
/// The Mac side (`NaruHelper --pair`) renders a QR in the terminal whose
/// payload is `naru://pair?code=<base64url(JSON)>` — the Orca pattern
/// (`orca://pair?code=…`, `~/repo/orca` `src/shared/pairing.ts`). The
/// iPhone side decodes the same string from three doors: the in-app
/// scanner, the system camera deep link, and the paste fallback, so this
/// type is the single parser all three share (FR-001).
///
/// Constitution §IV: the decoded offer carries the pairing secret and —
/// when the founder opted in at `--pair` time — the VNC password, so it
/// exists in transit, in memory, and in Keychain, never in the profile
/// store and never in logs. `NaruPairingOfferError` is deliberately a
/// fixed catalog: it classifies, it does not echo payload bytes.
public struct NaruPairingOffer: Equatable, Sendable {
    public struct Host: Equatable, Sendable {
        /// Human label for the profile ("MacBook Pro").
        public var label: String
        /// MagicDNS name when resolvable ("hckim-macbookpro"); nil when
        /// the Mac could not resolve its own tailnet name.
        public var magicDns: String?
        /// Tailscale CGNAT addresses (100.64/10) to try when the name
        /// fails or MagicDNS is off.
        public var addresses: [String]
        /// VNC (RFB) port the Mac serves; 5900 unless overridden.
        public var vncPort: UInt16

        public init(
            label: String,
            magicDns: String? = nil,
            addresses: [String],
            vncPort: UInt16 = 5900
        ) {
            self.label = label
            self.magicDns = magicDns
            self.addresses = addresses
            self.vncPort = vncPort
        }
    }

    public struct Helper: Equatable, Sendable {
        public var textPort: UInt16
        public var videoPort: UInt16
        /// The pairing secret (unpadded base64url, minted per `--pair`).
        public var token: String
        /// `sha256:` + 64 lowercase hex — `HelperPairingSecret.fingerprint`
        /// over `token`; rotates with it.
        public var fingerprint: String

        public init(
            textPort: UInt16 = UInt16(naruHelperTextBridgeDefaultPort),
            videoPort: UInt16 = UInt16(naruHelperVideoStreamDefaultPort),
            token: String,
            fingerprint: String
        ) {
            self.textPort = textPort
            self.videoPort = videoPort
            self.token = token
            self.fingerprint = fingerprint
        }
    }

    /// Payload schema version. Bumped on any breaking field change; the
    /// decoder refuses other values rather than guessing.
    public static let version = 1

    public var host: Host
    public var helper: Helper
    /// The Mac's VNC password, included only when the founder passed it
    /// to `--pair` via env indirection (`--vnc-password-env`). Stored to
    /// Keychain by the confirm sheet; `nil` means the app asks on first
    /// connect.
    public var vncPassword: String?

    public init(host: Host, helper: Helper, vncPassword: String? = nil) {
        self.host = host
        self.helper = helper
        self.vncPassword = vncPassword
    }
}

// MARK: - Wire format

public enum NaruPairingOfferError: Error, Equatable, Sendable {
    /// Input longer than the fixed cap — refuses padded/zip-bomb codes.
    case inputTooLong
    /// Not `naru://pair?code=…`: wrong scheme, wrong host, a non-empty
    /// path, or no `code` query item.
    case malformedURL
    /// The code is not canonical unpadded base64url.
    case malformedCode
    /// JSON body missing / not decodable under the v1 schema.
    case malformedPayload
    /// `v` is not 1.
    case unsupportedVersion
    /// A field exceeded its schema cap or violated its charset rule.
    case invalidField
    /// No addresses and no MagicDNS name — nowhere to connect.
    case noReachableAddress
}

public enum NaruPairingOfferWire {
    /// Wire caps (Orca-style belt on every string; constants, not guesses).
    public static let scheme = "naru"
    public static let urlHost = "pair"
    public static let codeQueryName = "code"
    public static let maxInputCharacters = 2_048
    public static let maxLabelCharacters = 128
    public static let maxAddressCharacters = 64
    public static let maxAddressCount = 4
    public static let maxTokenCharacters = 128
    public static let maxVncPasswordCharacters = 256

    static let base64urlCharset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// Encodes an offer to `naru://pair?code=<base64url(JSON)>`.
    /// The code rides a query parameter, never a fragment — Orca's
    /// measured lesson that Android camera intents and router layers
    /// preserve query params more reliably.
    public static func encode(_ offer: NaruPairingOffer) throws -> String {
        let object = WireObject(offer)
        // Deterministic bytes (spec 041 FR-003): Foundation's JSONEncoder
        // orders keys arbitrarily per call, so two encodes of equal input
        // differed in one process (measured 2026-09-05). Sorted keys make
        // the app's QR and the CLI's QR carry the same code for the same
        // inputs; decoders never depended on key order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(object)
        var code = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if code.count > maxInputCharacters {
            // Encoding our own validated fields cannot exceed the cap;
            // this arm exists so the invariant has a guard, not a hope.
            throw NaruPairingOfferError.inputTooLong
        }
        if code.isEmpty {
            throw NaruPairingOfferError.malformedCode
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = urlHost
        components.queryItems = [URLQueryItem(name: codeQueryName, value: code)]
        guard let url = components.url else {
            throw NaruPairingOfferError.malformedURL
        }
        return url.absoluteString
    }

    /// Dual-accept decode (Orca `parsePairingCode` parity): the full
    /// `naru://pair?code=…` URL — what the scanner and deep link deliver —
    /// or the bare base64url code — what the paste fallback receives when
    /// a terminal font mangles the QR.
    public static func decode(_ input: String) throws -> NaruPairingOffer {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxInputCharacters else {
            throw NaruPairingOfferError.inputTooLong
        }
        // Anything URL-shaped goes down the URL branch so a wrong scheme
        // reports as a URL problem, not a charset problem.
        if trimmed.contains("://") {
            return try decodeURL(trimmed)
        }
        return try decodeCode(trimmed)
    }

    private static func decodeURL(_ input: String) throws -> NaruPairingOffer {
        guard let components = URLComponents(string: input),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == urlHost,
              components.path.isEmpty || components.path == "/"
        else {
            throw NaruPairingOfferError.malformedURL
        }
        // Only the `code` query item may carry runtime auth material —
        // `naru://pairing?…` and friends are refused, not prefix-matched
        // (Orca's exact-host lesson).
        let code = components.queryItems?.first { $0.name == codeQueryName }?.value
        guard let code, !code.isEmpty else {
            throw NaruPairingOfferError.malformedURL
        }
        return try decodeCode(code)
    }

    private static func decodeCode(_ code: String) throws -> NaruPairingOffer {
        guard !code.isEmpty, code.count <= maxInputCharacters,
              code.unicodeScalars.allSatisfy({ base64urlCharset.contains($0) })
        else {
            throw NaruPairingOfferError.malformedCode
        }
        var base64 = code
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else {
            throw NaruPairingOfferError.malformedCode
        }
        let object: WireObject
        do {
            object = try JSONDecoder().decode(WireObject.self, from: data)
        } catch {
            throw NaruPairingOfferError.malformedPayload
        }
        return try object.validated()
    }

    // MARK: JSON mirror — Decodable gives unknown-key tolerance for free,
    // and every field re-validates on the way out so a hostile code can
    // never smuggle an oversized string past the caps.

    fileprivate struct WireObject: Codable {
        var v: Int
        var host: HostObject
        var helper: HelperObject
        var vncPassword: String?

        init(_ offer: NaruPairingOffer) {
            v = NaruPairingOffer.version
            host = HostObject(offer.host)
            helper = HelperObject(offer.helper)
            vncPassword = offer.vncPassword
        }

        struct HostObject: Codable {
            var label: String
            var magicDns: String?
            var addresses: [String]
            var vncPort: UInt16

            init(_ host: NaruPairingOffer.Host) {
                label = host.label
                magicDns = host.magicDns
                addresses = host.addresses
                vncPort = host.vncPort
            }
        }

        struct HelperObject: Codable {
            var textPort: UInt16
            var videoPort: UInt16
            var token: String
            var fingerprint: String

            init(_ helper: NaruPairingOffer.Helper) {
                textPort = helper.textPort
                videoPort = helper.videoPort
                token = helper.token
                fingerprint = helper.fingerprint
            }
        }
    }
}

private extension NaruPairingOfferWire.WireObject {
    func validated() throws -> NaruPairingOffer {
        guard v == NaruPairingOffer.version else {
            throw NaruPairingOfferError.unsupportedVersion
        }
        try NaruPairingOfferFieldValidator.validateLabel(host.label)
        if let magicDns = host.magicDns {
            try NaruPairingOfferFieldValidator.validateAddress(magicDns)
        }
        guard !host.addresses.isEmpty, host.addresses.count <= NaruPairingOfferWire.maxAddressCount,
              host.vncPort > 0
        else {
            if host.addresses.isEmpty, host.magicDns == nil {
                throw NaruPairingOfferError.noReachableAddress
            }
            throw NaruPairingOfferError.invalidField
        }
        for address in host.addresses {
            try NaruPairingOfferFieldValidator.validateAddress(address)
        }
        guard helper.textPort > 0, helper.videoPort > 0,
              !helper.token.isEmpty, helper.token.count <= NaruPairingOfferWire.maxTokenCharacters,
              helper.token.unicodeScalars.allSatisfy({ NaruPairingOfferWire.base64urlCharset.contains($0) })
        else {
            throw NaruPairingOfferError.invalidField
        }
        try NaruPairingOfferFieldValidator.validateFingerprint(helper.fingerprint)
        if let vncPassword {
            guard !vncPassword.isEmpty, vncPassword.count <= NaruPairingOfferWire.maxVncPasswordCharacters
            else {
                throw NaruPairingOfferError.invalidField
            }
        }
        return NaruPairingOffer(
            host: .init(
                label: host.label,
                magicDns: host.magicDns,
                addresses: host.addresses,
                vncPort: host.vncPort
            ),
            helper: .init(
                textPort: helper.textPort,
                videoPort: helper.videoPort,
                token: helper.token,
                fingerprint: helper.fingerprint
            ),
            vncPassword: vncPassword
        )
    }
}

/// Field rules shared by encode (self-check) and decode (hostile input).
/// Kept internal so the public surface stays the offer + error catalog.
enum NaruPairingOfferFieldValidator {
    static func validateLabel(_ label: String) throws {
        guard !label.isEmpty, label.count <= NaruPairingOfferWire.maxLabelCharacters else {
            throw NaruPairingOfferError.invalidField
        }
    }

    static func validateAddress(_ address: String) throws {
        guard !address.isEmpty, address.count <= NaruPairingOfferWire.maxAddressCharacters,
              address.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".:-")).contains($0) })
        else {
            throw NaruPairingOfferError.invalidField
        }
    }

    /// `sha256:` + exactly 64 lowercase hex — the format
    /// `HelperPairingSecret.fingerprint` produces and the profile editor
    /// already persists (spec 010); drift here would break re-pairing.
    static func validateFingerprint(_ fingerprint: String) throws {
        let hexCharset = CharacterSet(charactersIn: "0123456789abcdef")
        guard fingerprint.hasPrefix("sha256:"),
              fingerprint.count == "sha256:".count + 64,
              fingerprint.dropFirst("sha256:".count).unicodeScalars.allSatisfy({ hexCharset.contains($0) })
        else {
            throw NaruPairingOfferError.invalidField
        }
    }
}
