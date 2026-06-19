import Combine
import Foundation
import NaruRemoteCore

public struct SessionFrameState: Equatable, Sendable {
    public var framebuffer: RFBRawFramebuffer?
    public var dirtyRectangles: [RFBFrameDamageRect]?
    public var changedPixelCount: Int?
    public var serverCursor: RFBServerCursor?

    public init(
        framebuffer: RFBRawFramebuffer? = nil,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        changedPixelCount: Int? = nil,
        serverCursor: RFBServerCursor? = nil
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.changedPixelCount = changedPixelCount.map { max($0, 0) }
        self.serverCursor = serverCursor
    }

    public var hasFramebuffer: Bool {
        framebuffer != nil
    }
}

public enum SessionFrameDeliveryPriority: Equatable, Sendable {
    case visual
    case viewportNavigation
    case textInput
}

@MainActor
public final class SessionFrameStore: ObservableObject {
    // Publish-side coalescing windows. The application worker
    // (`SessionFrameApplicationWorkerPacing`) is the upstream rate
    // authority — it already caps how often content frames reach this
    // store and coalesces to the newest — so these windows only need to
    // merge a burst that lands inside a single run-loop tick before the
    // SwiftUI publish. They are kept near-zero (latency-priority): a
    // larger window here is pure redundant latency on top of the worker
    // cap. The earlier 16/50/100 ms windows stacked a second rate cap and
    // were the dominant self-inflicted delay while typing.
    static let steadyFrameDeliveryCoalescingDelay: Duration = .milliseconds(4)
    static let viewportNavigationFrameDeliveryCoalescingDelay: Duration = .milliseconds(8)
    static let textInputFrameDeliveryCoalescingDelay: Duration = .milliseconds(8)

    public private(set) var state: SessionFrameState

    /// Bumps only when SwiftUI needs to rebuild the viewport shell: first
    /// frame, framebuffer size changes, or clear. Steady-state content frames
    /// flow through `framePublisher` so touch/input chrome does not pay a
    /// SwiftUI diff cost at video cadence.
    @Published public private(set) var presentationRevision: Int

    private let frameSubject = PassthroughSubject<SessionFrameState, Never>()
    private var deliveryPriority: SessionFrameDeliveryPriority = .visual
    private var pendingFrameDelivery: SessionFrameState?
    private var pendingFrameDeliveryCoalescingDelay: Duration?
    private var frameDeliveryTask: Task<Void, Never>?

    public init(state: SessionFrameState = SessionFrameState()) {
        self.state = state
        self.presentationRevision = 0
    }

    deinit {
        frameDeliveryTask?.cancel()
    }

    public var framePublisher: AnyPublisher<SessionFrameState, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public var framebuffer: RFBRawFramebuffer? {
        state.framebuffer
    }

    public var dirtyRectangles: [RFBFrameDamageRect]? {
        state.dirtyRectangles
    }

    public var changedPixelCount: Int? {
        state.changedPixelCount
    }

    public var serverCursor: RFBServerCursor? {
        state.serverCursor
    }

    public func setDeliveryPriority(_ priority: SessionFrameDeliveryPriority) {
        guard deliveryPriority != priority else {
            return
        }

        deliveryPriority = priority
        switch priority {
        case .visual:
            // Leaving active input should make the latest remote frame visible
            // immediately instead of waiting for the longer keyboard-friendly
            // coalescing window to expire.
            frameDeliveryTask?.cancel()
            frameDeliveryTask = nil
            flushPendingFrameDelivery()
        case .viewportNavigation, .textInput:
            reschedulePendingSteadyFrameDelivery()
        }
    }

    public func publish(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]?,
        changedPixelCount: Int?,
        serverCursor: RFBServerCursor?
    ) {
        let previous = state
        let next = SessionFrameState(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            serverCursor: serverCursor ?? state.serverCursor
        )
        let requiresPresentationRefresh = Self.requiresPresentationRefresh(
            previous: previous,
            next: next
        )
        state = next
        scheduleFrameDelivery(
            next,
            coalescingDelay: requiresPresentationRefresh
                ? nil
                : currentSteadyFrameDeliveryCoalescingDelay
        )
        publishPresentationChangeIfNeeded(requiresPresentationRefresh)
    }

    public func publishServerCursor(_ serverCursor: RFBServerCursor) {
        let previous = state
        state.serverCursor = serverCursor
        let requiresPresentationRefresh = Self.requiresPresentationRefresh(
            previous: previous,
            next: state
        )
        scheduleFrameDelivery(
            state,
            coalescingDelay: requiresPresentationRefresh
                ? nil
                : currentSteadyFrameDeliveryCoalescingDelay
        )
        publishPresentationChangeIfNeeded(requiresPresentationRefresh)
    }

    public func clear() {
        let previous = state
        state = SessionFrameState()
        let requiresPresentationRefresh = Self.requiresPresentationRefresh(
            previous: previous,
            next: state
        )
        scheduleFrameDelivery(state, coalescingDelay: nil)
        publishPresentationChangeIfNeeded(requiresPresentationRefresh)
    }

    func flushPendingFrameDeliveryForTesting() {
        frameDeliveryTask?.cancel()
        frameDeliveryTask = nil
        flushPendingFrameDelivery()
    }

    var pendingFrameDeliveryCoalescingDelayForTesting: Duration? {
        pendingFrameDeliveryCoalescingDelay
    }

    var currentSteadyFrameDeliveryCoalescingDelay: Duration {
        switch deliveryPriority {
        case .visual:
            return Self.steadyFrameDeliveryCoalescingDelay
        case .viewportNavigation:
            return Self.viewportNavigationFrameDeliveryCoalescingDelay
        case .textInput:
            return Self.textInputFrameDeliveryCoalescingDelay
        }
    }

    private func scheduleFrameDelivery(
        _ next: SessionFrameState,
        coalescingDelay: Duration?
    ) {
        pendingFrameDelivery = next
        pendingFrameDeliveryCoalescingDelay = coalescingDelay
        if coalescingDelay == nil {
            frameDeliveryTask?.cancel()
            frameDeliveryTask = Task { @MainActor [weak self] in
                await Task.yield()
                self?.flushPendingFrameDelivery()
            }
            return
        }

        guard frameDeliveryTask == nil else {
            return
        }

        guard let delay = coalescingDelay else {
            return
        }
        frameDeliveryTask = makeDelayedFrameFlushTask(after: delay)
    }

    private func reschedulePendingSteadyFrameDelivery() {
        guard pendingFrameDelivery != nil,
              pendingFrameDeliveryCoalescingDelay != nil else {
            return
        }

        pendingFrameDeliveryCoalescingDelay = currentSteadyFrameDeliveryCoalescingDelay
        frameDeliveryTask?.cancel()
        guard let delay = pendingFrameDeliveryCoalescingDelay else {
            return
        }
        frameDeliveryTask = makeDelayedFrameFlushTask(after: delay)
    }

    /// Schedules a single coalesced flush after `delay`. Used by both the
    /// initial schedule and the steady-state reschedule path so the
    /// sleep/cancel/flush lifecycle lives in one place.
    private func makeDelayedFrameFlushTask(after delay: Duration) -> Task<Void, Never> {
        Task { @MainActor [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.flushPendingFrameDelivery()
        }
    }

    private func flushPendingFrameDelivery() {
        frameDeliveryTask = nil
        guard let next = pendingFrameDelivery else {
            return
        }
        pendingFrameDelivery = nil
        pendingFrameDeliveryCoalescingDelay = nil
        frameSubject.send(next)
    }

    private func publishPresentationChangeIfNeeded(_ requiresPresentationRefresh: Bool) {
        guard requiresPresentationRefresh else {
            return
        }
        presentationRevision += 1
    }

    private static func requiresPresentationRefresh(
        previous: SessionFrameState,
        next: SessionFrameState
    ) -> Bool {
        framebufferSize(previous.framebuffer) != framebufferSize(next.framebuffer)
    }

    private static func framebufferSize(_ framebuffer: RFBRawFramebuffer?) -> FramebufferSize? {
        guard let framebuffer else {
            return nil
        }
        return FramebufferSize(width: framebuffer.width, height: framebuffer.height)
    }
}

private struct FramebufferSize: Equatable {
    let width: Int
    let height: Int
}
