import Foundation

public struct FakeRFBTranscript: Equatable, Sendable {
    public let bytes: Data

    public init(bytes: Data) {
        self.bytes = bytes
    }

    public static func loadHexFile(at url: URL) throws -> FakeRFBTranscript {
        let text = try String(contentsOf: url, encoding: .utf8)
        let hexPairs = text
            .split(whereSeparator: \.isNewline)
            .flatMap { line -> [Substring] in
                let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                return content.split(whereSeparator: \.isWhitespace)
            }

        return FakeRFBTranscript(
            bytes: Data(try hexPairs.map { pair in
                guard let byte = UInt8(pair, radix: 16) else {
                    throw FakeRFBTranscriptError.invalidHexByte(String(pair))
                }
                return byte
            })
        )
    }
}

public enum FakeRFBTranscriptError: Error, Equatable, LocalizedError {
    case invalidHexByte(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHexByte(let value):
            return "Invalid hex byte in fake RFB transcript: \(value)"
        }
    }
}
