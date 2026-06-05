public enum BenchmarkStreamShapePreflightFrames {
    public static let defaultValue = 0
    public static let maximum = 5
    public static let usageDescription = "0...\(maximum)"

    public static func parse(_ rawValue: String) throws -> Int {
        guard let frames = Int(rawValue), (defaultValue...maximum).contains(frames) else {
            throw BenchmarkStreamShapePreflightFramesError.outOfRange
        }
        return frames
    }

    public static func clamped(_ frames: Int) -> Int {
        min(max(frames, defaultValue), maximum)
    }
}

public enum BenchmarkStreamShapePreflightFramesError: Error, Equatable, Sendable {
    case outOfRange

    public var message: String {
        "stream-shape-preflight-frames must be an integer from 0 to \(BenchmarkStreamShapePreflightFrames.maximum)."
    }
}
