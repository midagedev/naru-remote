import CommonCrypto
import Foundation

public enum RFBSecurityType: UInt8, Codable, Equatable, Sendable {
    case none = 1
    case vncAuthentication = 2
}

public enum RFBConnectionCredential: Equatable, Sendable {
    case none
    case vncPassword(String)
}

public enum RFBVNCAuthenticationError: Error, Equatable, LocalizedError {
    case invalidChallengeLength(Int)
    case encryptionFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidChallengeLength(let length):
            "VNC authentication challenge must be 16 bytes. Received \(length)."
        case .encryptionFailed(let status):
            "VNC authentication response encryption failed with status \(status)."
        }
    }
}

public enum RFBVNCAuthentication {
    public static func response(password: String, challenge: Data) throws -> Data {
        guard challenge.count == 16 else {
            throw RFBVNCAuthenticationError.invalidChallengeLength(challenge.count)
        }

        let key = passwordKey(password)
        var output = Data(count: challenge.count)
        let outputCapacity = output.count
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            challenge.withUnsafeBytes { challengeBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmDES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        kCCKeySizeDES,
                        nil,
                        challengeBuffer.baseAddress,
                        challenge.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw RFBVNCAuthenticationError.encryptionFailed(status)
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    static func passwordKey(_ password: String) -> Data {
        var bytes = Array(password.utf8.prefix(8))
        if bytes.count < 8 {
            bytes.append(contentsOf: Array(repeating: 0, count: 8 - bytes.count))
        }

        return Data(bytes.map(reverseBits))
    }

    private static func reverseBits(_ byte: UInt8) -> UInt8 {
        var value = byte
        var reversed: UInt8 = 0

        for _ in 0..<8 {
            reversed = (reversed << 1) | (value & 1)
            value >>= 1
        }

        return reversed
    }
}
