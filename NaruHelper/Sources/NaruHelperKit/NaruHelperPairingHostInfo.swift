import Darwin
import Foundation

/// Best-effort host identity for the pairing offer (spec 040 FR-003,
/// lifted from the CLI for spec 041 so the menu bar app and `--pair`
/// answer the same question with the same code): the computer name, the
/// Mac's Tailscale CGNAT addresses, and the MagicDNS name when the machine
/// can reverse-resolve its own tailnet address.
///
/// `current()` returns nil when no tailnet address exists — Naru refuses
/// to pair over public internet (constitution §II), and the caller states
/// that plainly instead of falling back to a LAN or public address.
public struct NaruHelperPairingHostInfo: Equatable, Sendable {
    public var label: String
    public var magicDns: String?
    public var addresses: [String]

    public init(label: String, magicDns: String? = nil, addresses: [String]) {
        self.label = label
        self.magicDns = magicDns
        self.addresses = addresses
    }

    /// Tailscale's CGNAT range is 100.64.0.0/10: octet 0 is 100 and
    /// octet 1 spans 64...127. Pure on purpose — the boundary is unit
    /// tested without interfaces.
    public static func isTailnetIPv4(_ octets: [UInt8]) -> Bool {
        octets.count == 4 && octets[0] == 100 && (64...127).contains(octets[1])
    }

    /// Blocking: the MagicDNS lookup is a synchronous `getnameinfo` that
    /// can take the resolver's full timeout (tens of seconds, measured
    /// 2026-09-06). Call it off the main actor in UI code.
    public static func current() -> NaruHelperPairingHostInfo? {
        #if os(macOS)
        let label = Host.current().localizedName ?? "Mac"
        let addresses = tailnetAddresses()
        guard !addresses.isEmpty else {
            return nil
        }
        return NaruHelperPairingHostInfo(
            label: label,
            magicDns: addresses.first.flatMap(magicDnsName(for:)),
            addresses: addresses
        )
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// IPv4 addresses inside Tailscale's CGNAT range (100.64.0.0/10).
    private static func tailnetAddresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }
        var result: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let sa = interface.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }
            var addr = sockaddr_in()
            memcpy(&addr, sa, min(Int(sa.pointee.sa_len), MemoryLayout<sockaddr_in>.size))
            let octets = withUnsafeBytes(of: addr.sin_addr) { Array($0) }
            guard isTailnetIPv4(octets) else {
                continue
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var copy = addr
            guard inet_ntop(AF_INET, &copy.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }
            let address = String(cString: buffer)
            if !result.contains(address) {
                result.append(address)
            }
        }
        return result
    }

    /// Reverse-resolve a tailnet address through the system resolver —
    /// with MagicDNS live this yields the machine's own ts.net name.
    private static func magicDnsName(for address: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address, &addr.sin_addr) == 1 else {
            return nil
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    &host,
                    socklen_t(NI_MAXHOST),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }
        guard status == 0 else {
            return nil
        }
        var name = String(cString: host)
        if name.hasSuffix(".") {
            name.removeLast()
        }
        return name.isEmpty ? nil : name
    }
    #endif
}
