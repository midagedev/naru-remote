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
    @Published public private(set) var state: SessionFrameState

    public init(state: SessionFrameState = SessionFrameState()) {
        self.state = state
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
        state = SessionFrameState(
            framebuffer: framebuffer,
            dirtyRectangles: dirtyRectangles,
            changedPixelCount: changedPixelCount,
            serverCursor: serverCursor ?? state.serverCursor
        )
    }

    public func publishServerCursor(_ serverCursor: RFBServerCursor) {
        state.serverCursor = serverCursor
    }

    public func clear() {
        state = SessionFrameState()
    }
}
