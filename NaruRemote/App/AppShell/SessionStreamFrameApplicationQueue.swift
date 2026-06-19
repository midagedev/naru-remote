import Foundation
import NaruRemoteCore

// Frame-application plumbing for the live session stream, extracted from
// `NaruRemoteAppModel.swift`. These three types are the single rate
// authority for how often decoded frames are applied: the work item, the
// per-priority pacing floors, and the bounded coalescing queue that feeds
// the @MainActor apply worker. None of them touch the app model, so they
// live on their own.

struct StreamFrameApplicationWork: Sendable {
    let frame: RFBFramePumpFrame
    let serverInit: RFBServerInit
    let profile: ConnectionProfile
    let sessionID: RemoteSession.ID
    let streamID: UUID
    let isEmptyUpdate: Bool
}

struct SessionFrameApplicationWorkerPacing: Equatable, Sendable {
    static let visualContentFrameMinimumInterval: TimeInterval = 1.0 / 60.0
    static let viewportNavigationContentFrameMinimumInterval: TimeInterval =
        StreamPressurePacingDefaults.transientInputContentFrameIntervalSeconds
    // Frame application cadence while the user is composing text. This is
    // the single rate authority that also feeds the request loop's
    // `activeInputPacingInterval`, so it governs both how often we request
    // *and* apply frames during typing. Latency-priority: a 30 Hz-class
    // floor keeps remote echo responsive while typing instead of the old
    // 10 Hz cap that pinned typing-time screen updates to ~100 ms. The
    // Core `textInputContentFrameIntervalSeconds` constant stays at its
    // documented 10 Hz-class value for the benchmark/pressure-threshold
    // mirror; this worker floor is intentionally decoupled from it.
    static let textInputContentFrameMinimumInterval: TimeInterval = 1.0 / 30.0
    static let defaultContentFrameMinimumInterval: TimeInterval =
        visualContentFrameMinimumInterval

    static func contentFrameMinimumInterval(
        for priority: SessionFrameDeliveryPriority
    ) -> TimeInterval {
        switch priority {
        case .visual:
            return visualContentFrameMinimumInterval
        case .viewportNavigation:
            return viewportNavigationContentFrameMinimumInterval
        case .textInput:
            return textInputContentFrameMinimumInterval
        }
    }

    func delay(
        before work: StreamFrameApplicationWork,
        lastContentFrameAppliedAt: Date?,
        now: Date,
        contentFrameMinimumInterval: TimeInterval = Self.defaultContentFrameMinimumInterval
    ) -> TimeInterval {
        guard !work.isEmptyUpdate else {
            return 0
        }
        guard let lastContentFrameAppliedAt else {
            return 0
        }
        return max(contentFrameMinimumInterval - now.timeIntervalSince(lastContentFrameAppliedAt), 0)
    }
}

actor SessionStreamFrameApplicationQueue {
    static let maximumPendingWorkCount = 3

    private var pending: [StreamFrameApplicationWork] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isClosed = false

    @discardableResult
    func enqueue(_ work: StreamFrameApplicationWork) -> Int {
        guard !isClosed else {
            return 0
        }
        pending.append(work)
        let droppedCount = coalescePending()
        resumePendingWaiters()
        return droppedCount
    }

    func next(preferControlUpdates: Bool = false) async -> StreamFrameApplicationWork? {
        while true {
            guard pending.isEmpty else {
                if preferControlUpdates,
                   let controlUpdateIndex = pending.firstIndex(where: \.isEmptyUpdate)
                {
                    return pending.remove(at: controlUpdateIndex)
                }
                return pending.removeFirst()
            }
            guard !isClosed else {
                return nil
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func pendingCount() -> Int {
        pending.count
    }

    func latestContentWork(replacing work: StreamFrameApplicationWork) -> StreamFrameApplicationWork {
        guard !work.isEmptyUpdate,
              let latestContentIndex = pending.indices.last(where: { !pending[$0].isEmptyUpdate })
        else {
            return work
        }

        let latest = pending.remove(at: latestContentIndex)
        pending.removeAll { !$0.isEmptyUpdate }
        return latest
    }

    func close() {
        isClosed = true
        resumePendingWaiters()
    }

    private func resumePendingWaiters() {
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    private func coalescePending() -> Int {
        guard pending.count > 1 else {
            return 0
        }

        let originalCount = pending.count
        let initialContentIndex = pending.indices.first {
            !pending[$0].frame.isIncremental && !pending[$0].isEmptyUpdate
        }
        let latestContentIndex = pending.indices.last {
            !pending[$0].isEmptyUpdate
        }
        let latestCursorIndex = pending.indices.last {
            pending[$0].isEmptyUpdate && pending[$0].frame.serverCursor != nil
        }
        let latestLivenessIndex = pending.indices.last {
            pending[$0].isEmptyUpdate && pending[$0].frame.serverCursor == nil
        }

        var retainedIndexes = Set<Int>()
        if let initialContentIndex {
            retainedIndexes.insert(initialContentIndex)
        }
        if let latestContentIndex {
            retainedIndexes.insert(latestContentIndex)
        }
        if let latestCursorIndex {
            retainedIndexes.insert(latestCursorIndex)
        }
        if retainedIndexes.isEmpty, let latestLivenessIndex {
            retainedIndexes.insert(latestLivenessIndex)
        }
        if retainedIndexes.isEmpty, let lastIndex = pending.indices.last {
            retainedIndexes.insert(lastIndex)
        }

        pending = pending.enumerated()
            .compactMap { retainedIndexes.contains($0.offset) ? $0.element : nil }
        if pending.count > Self.maximumPendingWorkCount {
            pending = Array(pending.suffix(Self.maximumPendingWorkCount))
        }
        return originalCount - pending.count
    }
}
