import Foundation

/// Which Swift build configuration produced a benchmark report.
///
/// This exists because a debug-built measurement is not a measurement. Debug
/// Swift leaves ZRLE inflate/tile-apply unoptimised, and the resulting client
/// processing cost dominates every timing the benchmark reports — measured
/// 2026-08-21 on the same live target, same stimulus, same flags: the debug
/// binary reported content frames per second under one and diagnosed
/// `local-processing-dominated`, while the release binary of the same commit
/// reported roughly an order of magnitude more and diagnosed
/// `first-byte-wait-dominated`. Those are not two readings of one quantity;
/// they are two different conclusions about where the bottleneck lives, and the
/// debug one is an artefact.
///
/// The damage from that is not confined to one run. A contaminated instrument
/// contaminates every judgement stacked on it: a production constant in this
/// repository (`requestPipelineDepth`) still carries a justification comment
/// whose numbers are in the debug range, and a lead session drew a "the server
/// caps at ~10 frames per second" conclusion from a debug-built probe. So every
/// report now states the configuration it was produced under, which makes an
/// archived report self-describing and lets a gate refuse to read timing
/// verdicts out of a debug run.
public enum BenchmarkBuildConfiguration: String, Codable, Equatable, Sendable, CaseIterable {
    case debug
    case release

    /// The configuration this binary was compiled with.
    public static var current: BenchmarkBuildConfiguration {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    /// Whether timing verdicts from a report in this configuration may be
    /// trusted. Label regressions and argument checks are still meaningful in
    /// debug; latency, frames per second and bottleneck attribution are not.
    public var producesTrustworthyTimings: Bool {
        self == .release
    }

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}
