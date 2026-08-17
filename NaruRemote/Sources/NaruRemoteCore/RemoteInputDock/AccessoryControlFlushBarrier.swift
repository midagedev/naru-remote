import Foundation

/// Ordering barrier so a strip / quick-key emission cannot overtake
/// in-flight Type composition (spec 012 US2-3).
///
/// Mirrors orca `commit-held-then-send` +
/// `sendTerminalLiveControlAfterPendingFlush`
/// (`docs/research/orca-mobile-input-reference.md` §2.2 / §6.2):
/// marked text is committed first, then any pending live insert is
/// drained; if that flush fails the control key is not sent.
public enum AccessoryControlFlushBarrier: Sendable {
    public enum PendingFlushResult: Sendable, Equatable {
        /// No helper/clipboard insert was in flight (key-lane work is
        /// already ordered by `OutboundInputEventDispatcher`).
        case notNeeded
        case succeeded
        case failed
    }

    public enum Step: Sendable, Equatable {
        case commitMarkedText
        case emitControl
        case dropControl
    }

    /// Ordered steps for a strip/quick-key tap. Callers must execute
    /// `commitMarkedText` before enqueueing the keysym when present.
    public static func steps(
        hasMarkedText: Bool,
        pendingFlush: PendingFlushResult
    ) -> [Step] {
        var steps: [Step] = []
        if hasMarkedText {
            steps.append(.commitMarkedText)
        }
        switch pendingFlush {
        case .notNeeded, .succeeded:
            steps.append(.emitControl)
        case .failed:
            steps.append(.dropControl)
        }
        return steps
    }

    /// Model-layer gate after a pending live-insert wait completes.
    /// `false` means drop the control and leave existing state alone.
    public static func shouldEmitAfterFlush(succeeded: Bool) -> Bool {
        succeeded
    }
}
