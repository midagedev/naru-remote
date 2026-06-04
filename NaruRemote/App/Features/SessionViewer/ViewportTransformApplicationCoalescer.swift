struct ViewportTransformApplicationCoalescer: Equatable, Sendable {
    private(set) var hasPendingApplication = false
    private(set) var hasScheduledDisplayLink = false

    mutating func requestDisplayLinkedApplication() -> Bool {
        hasPendingApplication = true
        guard !hasScheduledDisplayLink else {
            return false
        }
        hasScheduledDisplayLink = true
        return true
    }

    mutating func flush() -> Bool {
        let shouldApply = hasPendingApplication
        hasPendingApplication = false
        hasScheduledDisplayLink = false
        return shouldApply
    }

    mutating func cancel() {
        hasPendingApplication = false
        hasScheduledDisplayLink = false
    }
}
