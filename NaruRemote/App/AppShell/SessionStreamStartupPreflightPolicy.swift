import Foundation

public struct SessionStreamStartupPreflightPolicy: Equatable, Sendable {
    public static let maximumHiddenFrameCount = 1
    public static let defaultRequestTimeout: TimeInterval = 1
    public static let disabled = SessionStreamStartupPreflightPolicy(hiddenFrameCount: 0)

    public let hiddenFrameCount: Int
    public let requestTimeout: TimeInterval

    public init(
        hiddenFrameCount: Int,
        requestTimeout: TimeInterval = defaultRequestTimeout
    ) {
        self.hiddenFrameCount = min(max(hiddenFrameCount, 0), Self.maximumHiddenFrameCount)
        self.requestTimeout = max(requestTimeout, 0)
    }
}
