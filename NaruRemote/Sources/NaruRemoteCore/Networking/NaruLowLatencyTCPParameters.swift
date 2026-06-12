import Foundation

#if canImport(Network)
import Network

enum NaruLowLatencyTCPParameters {
    static func make() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        return NWParameters(tls: nil, tcp: tcpOptions)
    }
}
#endif
