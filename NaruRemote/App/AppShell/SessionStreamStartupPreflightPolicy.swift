import Foundation
import NaruRemoteCore

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

    public init(
        mode: StreamStartupPreflightMode,
        requestTimeout: TimeInterval = defaultRequestTimeout
    ) {
        self.init(
            hiddenFrameCount: mode.requestedHiddenFrameCount,
            requestTimeout: requestTimeout
        )
    }
}

public struct SessionStreamStartupPreflightResult: Equatable, Sendable {
    public static let notRequested = SessionStreamStartupPreflightResult(
        requestedHiddenFrameCount: 0,
        consumedHiddenFrameCount: 0,
        outcome: .notRequested
    )

    public let requestedHiddenFrameCount: Int
    public let consumedHiddenFrameCount: Int
    public let outcome: DiagnosticStartupPreflightOutcome

    public init(
        requestedHiddenFrameCount: Int,
        consumedHiddenFrameCount: Int,
        outcome: DiagnosticStartupPreflightOutcome
    ) {
        let requested = min(
            max(requestedHiddenFrameCount, 0),
            SessionStreamStartupPreflightPolicy.maximumHiddenFrameCount
        )
        self.requestedHiddenFrameCount = requested
        self.consumedHiddenFrameCount = min(max(consumedHiddenFrameCount, 0), requested)
        self.outcome = requested == 0 ? .notRequested : outcome
    }
}
