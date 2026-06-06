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

@MainActor
public final class SessionFrameStore: ObservableObject {
    public private(set) var state: SessionFrameState

    /// Bumps only when SwiftUI needs to rebuild the viewport shell: first
    /// frame, framebuffer size changes, or clear. Steady-state content frames
    /// flow through `framePublisher` so touch/input chrome does not pay a
    /// SwiftUI diff cost at video cadence.
    @Published public private(set) var presentationRevision: Int

    private let frameSubject = PassthroughSubject<SessionFrameState, Never>()

    public init(state: SessionFrameState = SessionFrameState()) {
        self.state = state
        self.presentationRevision = 0
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
        state = next
        frameSubject.send(next)
        publishPresentationChangeIfNeeded(previous: previous, next: next)
    }

    public func publishServerCursor(_ serverCursor: RFBServerCursor) {
        let previous = state
        state.serverCursor = serverCursor
        frameSubject.send(state)
        publishPresentationChangeIfNeeded(previous: previous, next: state)
    }

    public func clear() {
        let previous = state
        state = SessionFrameState()
        frameSubject.send(state)
        publishPresentationChangeIfNeeded(previous: previous, next: state)
    }

    private func publishPresentationChangeIfNeeded(
        previous: SessionFrameState,
        next: SessionFrameState
    ) {
        guard Self.requiresPresentationRefresh(previous: previous, next: next) else {
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
