import Foundation

public struct ConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    public enum HostKind: String, Codable, Equatable, Sendable {
        case magicDNS
        case privateAddress
        case advancedManualPublicEndpoint
    }

    public let id: UUID
    public var displayName: String
    public var host: String
    public var port: Int
    public var username: String?
    public var credentialRef: String?
    public var favorite: Bool
    public var lastConnectedAt: Date?
    public var lastDiagnosticSummary: String?
    public var hostKind: HostKind
    public var allowsPiPWatch: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int = 5900,
        username: String? = nil,
        credentialRef: String? = nil,
        favorite: Bool = false,
        lastConnectedAt: Date? = nil,
        lastDiagnosticSummary: String? = nil,
        hostKind: HostKind = .magicDNS,
        allowsPiPWatch: Bool = true
    ) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw ConnectionProfileValidationError.emptyDisplayName
        }

        guard !trimmedHost.isEmpty else {
            throw ConnectionProfileValidationError.emptyHost
        }

        guard (1...65535).contains(port) else {
            throw ConnectionProfileValidationError.invalidPort(port)
        }

        self.id = id
        self.displayName = trimmedName
        self.host = trimmedHost
        self.port = port
        self.username = username?.nilIfBlank
        self.credentialRef = credentialRef?.nilIfBlank
        self.favorite = favorite
        self.lastConnectedAt = lastConnectedAt
        self.lastDiagnosticSummary = lastDiagnosticSummary?.nilIfBlank
        self.hostKind = hostKind
        self.allowsPiPWatch = allowsPiPWatch
    }

    public var endpoint: String {
        "\(host):\(port)"
    }
}

public extension ConnectionProfile {
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case host
        case port
        case username
        case credentialRef
        case favorite
        case lastConnectedAt
        case lastDiagnosticSummary
        case hostKind
        case allowsPiPWatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            id: container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            displayName: container.decode(String.self, forKey: .displayName),
            host: container.decode(String.self, forKey: .host),
            port: container.decodeIfPresent(Int.self, forKey: .port) ?? 5900,
            username: container.decodeIfPresent(String.self, forKey: .username),
            credentialRef: container.decodeIfPresent(String.self, forKey: .credentialRef),
            favorite: container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false,
            lastConnectedAt: container.decodeIfPresent(Date.self, forKey: .lastConnectedAt),
            lastDiagnosticSummary: container.decodeIfPresent(String.self, forKey: .lastDiagnosticSummary),
            hostKind: container.decodeIfPresent(HostKind.self, forKey: .hostKind) ?? .magicDNS,
            allowsPiPWatch: container.decodeIfPresent(Bool.self, forKey: .allowsPiPWatch) ?? true
        )
    }
}

public enum ConnectionProfileValidationError: Error, Equatable, LocalizedError {
    case emptyDisplayName
    case emptyHost
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            "Profile name is required."
        case .emptyHost:
            "Host is required."
        case .invalidPort(let port):
            "VNC port must be between 1 and 65535. Received \(port)."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
