import NaruRemoteCore
import SwiftUI

/// Gate for the live performance HUD. DEBUG builds can opt in via the
/// `NARU_PERF_HUD` launch environment variable so normal simulator UX
/// audits and founder walkthroughs don't carry a development overlay.
/// Release builds keep the gate closed.
enum SessionPerformanceHUDGate {
    static let isEnabled: Bool = {
#if DEBUG
        let raw = ProcessInfo.processInfo.environment["NARU_PERF_HUD"]
        guard let raw, !raw.isEmpty else { return false }
        return raw != "0" && raw.lowercased() != "false"
#else
        false
#endif
    }()
}

/// A DEBUG-only live readout of the already-collected
/// `SessionStreamStats`. Nothing here is new instrumentation — every value
/// is a computed accessor that the model already aggregates per frame for
/// pacing decisions and the diagnostic export. The HUD just surfaces those
/// numbers on screen so the binding performance ceiling (network RTT vs.
/// CPU decode vs. GPU upload vs. our own pacing delay vs. input round-trip)
/// is visible *while interacting*, instead of only after a coarse,
/// bucketed export.
///
/// Frame pixels are intentionally isolated from the app-model
/// `ObservableObject` so the shell does not re-render every frame, which
/// means `sessionStreamStats` mutations do not drive SwiftUI invalidation.
/// The HUD therefore self-refreshes on a `TimelineView` cadence rather than
/// observing the model — a ~2 Hz tick is plenty for aggregates and adds no
/// per-frame churn.
struct SessionPerformanceHUDView: View {
    /// Held as a plain reference (not `@ObservedObject`) on purpose: the
    /// HUD must not couple shell invalidation to stream stats. Reads happen
    /// inside the `TimelineView` tick.
    let model: NaruRemoteAppModel

    @State private var isExpanded = true

    private static let refreshInterval: TimeInterval = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
            content(stats: model.sessionStreamStats)
        }
    }

    @ViewBuilder
    private func content(stats: SessionStreamStats) -> some View {
        if isExpanded {
            expanded(stats: stats)
        } else {
            collapsedChip(stats: stats)
        }
    }

    private func collapsedChip(stats: SessionStreamStats) -> some View {
        Button {
            isExpanded = true
        } label: {
            HStack(spacing: 6) {
                Text("⏱")
                Text(fpsText(stats.contentFramesPerSecond))
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.65), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func expanded(stats: SessionStreamStats) -> some View {
        let ceiling = bindingCeiling(stats: stats)
        return VStack(alignment: .leading, spacing: 2) {
            header(stats: stats)
            divider
            row("net read", stats.averageNetworkReadMilliseconds, stats.maxNetworkReadMilliseconds, highlight: ceiling == .network)
            row("decode", stats.averageClientProcessingMilliseconds, stats.maxClientProcessingMilliseconds, highlight: ceiling == .decode)
            row("gpu up", stats.averageRendererUploadMilliseconds, stats.maxRendererUploadMilliseconds, highlight: ceiling == .upload)
            row("apply", stats.averageAppFrameApplyMilliseconds, stats.maxAppFrameApplyMilliseconds, highlight: ceiling == .apply)
            row("pacing", stats.averageStreamPacingDelayMilliseconds, stats.maxStreamPacingDelayMilliseconds, highlight: ceiling == .pacing)
            divider
            row("in queue", stats.averageOutboundInputQueueDelayMilliseconds, stats.maxOutboundInputQueueDelayMilliseconds, highlight: false)
            row("in op", stats.averageOutboundInputOperationMilliseconds, stats.maxOutboundInputOperationMilliseconds, highlight: false)
            row("main blk", stats.averageMainActorResponsivenessDelayMilliseconds, stats.maxMainActorResponsivenessDelayMilliseconds, highlight: false)
            if stats.outboundInputEventTimeoutCount > 0 {
                Text("input timeouts: \(stats.outboundInputEventTimeoutCount)")
                    .foregroundStyle(NaruColors.warning)
            }
            divider
            pacingReasonRow(stats)
            encodingRow(stats.actualEncodingMix)
            ceilingRow(ceiling)
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 230, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded = false }
    }

    private func header(stats: SessionStreamStats) -> some View {
        HStack(spacing: 6) {
            Text("PERF")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Spacer(minLength: 4)
            Text("\(fpsText(stats.contentFramesPerSecond)) fps")
                .monospacedDigit()
            Text("· \(stats.contentFrameCount)f")
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
        // Machine-readable liveness signal for the live UI probes. The
        // 2026-08-21 freeze (spec 022) was only visible on a device because
        // the HUD published its frame count as pixels: a UI test could
        // screenshot it but not assert on it. Counts only (constitution §IV),
        // and this whole view is already `NARU_PERF_HUD`-gated.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("naru.session.perf.contentFrameCount")
        .accessibilityValue(String(stats.contentFrameCount))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 1)
    }

    private func row(_ label: String, _ average: Int?, _ maximum: Int?, highlight: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .frame(width: 58, alignment: .leading)
                .foregroundStyle(highlight ? .yellow : .white.opacity(0.85))
            Spacer(minLength: 2)
            Text(msText(average))
                .monospacedDigit()
                .foregroundStyle(highlight ? .yellow : .white)
            Text("/")
                .foregroundStyle(.white.opacity(0.4))
            Text(msText(maximum))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            Text("ms")
                .foregroundStyle(.white.opacity(0.4))
        }
        .fontWeight(highlight ? .bold : .regular)
    }

    private func encodingRow(_ mix: RFBFramebufferEncodingMix) -> some View {
        let parts: [String] = [
            mix.rawRectangles > 0 ? "raw \(mix.rawRectangles)" : nil,
            mix.zrleRectangles > 0 ? "zrle \(mix.zrleRectangles)" : nil,
            mix.hextileRectangles > 0 ? "hex \(mix.hextileRectangles)" : nil,
            mix.tightRectangles > 0 ? "tight \(mix.tightRectangles)" : nil,
            mix.copyRectRectangles > 0 ? "copy \(mix.copyRectRectangles)" : nil,
        ].compactMap { $0 }
        return Text("enc: \(parts.isEmpty ? "—" : parts.joined(separator: " "))")
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Attributes the artificial pacing delay to its dominant source so a
    /// high `pacing` row is actionable: `idle` = static-screen backoff
    /// (benign), `input`/`viewport` = interaction throttle, `thermal`/
    /// `power`/`pressure` = adaptive backoff under constraint.
    private func pacingReasonRow(_ stats: SessionStreamStats) -> some View {
        let reasons: [(String, Int)] = [
            ("idle", stats.emptyBackoffPacingSampleCount),
            ("input", stats.activeInputPacingSampleCount),
            ("viewport", stats.viewportInteractionPacingSampleCount),
            ("thermal", stats.thermalPacingSampleCount),
            ("power", stats.powerSaverPacingSampleCount),
            ("pressure", stats.adaptiveClientPressurePacingSampleCount),
        ].filter { $0.1 > 0 }
        let text = reasons.isEmpty
            ? "pacing src: —"
            : "pacing src: " + reasons
                .sorted { $0.1 > $1.1 }
                .map { "\($0.0) \($0.1)" }
                .joined(separator: " ")
        return Text(text)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func ceilingRow(_ ceiling: BindingCeiling?) -> some View {
        Text("ceiling: \(ceiling?.label ?? "—")")
            .foregroundStyle(.cyan)
            .fontWeight(.semibold)
    }

    // MARK: - Bottleneck heuristic

    private enum BindingCeiling: Equatable {
        case network, decode, upload, apply, pacing, mainActor

        var label: String {
            switch self {
            case .network: return "network (RTT/server)"
            case .decode: return "decode (CPU)"
            case .upload: return "gpu upload"
            case .apply: return "frame apply"
            case .pacing: return "our pacing delay"
            case .mainActor: return "main-actor stall"
            }
        }
    }

    /// Picks the largest average contributor to per-frame latency. This is
    /// a coarse pointer, not a verdict — `net wait` dominating means the
    /// request/response round-trip binds (raise pipelining / continuous
    /// updates); `decode` dominating means CPU binds (move pixel
    /// conversion to the GPU); `pacing` dominating means *we* are the
    /// limiter (our own throttle is too aggressive for this network).
    private func bindingCeiling(stats: SessionStreamStats) -> BindingCeiling? {
        let candidates: [(BindingCeiling, Int)] = [
            (.network, stats.averageNetworkReadMilliseconds ?? 0),
            (.decode, stats.averageClientProcessingMilliseconds ?? 0),
            (.upload, stats.averageRendererUploadMilliseconds ?? 0),
            (.apply, stats.averageAppFrameApplyMilliseconds ?? 0),
            (.pacing, stats.averageStreamPacingDelayMilliseconds ?? 0),
            (.mainActor, stats.averageMainActorResponsivenessDelayMilliseconds ?? 0),
        ]
        guard let top = candidates.max(by: { $0.1 < $1.1 }), top.1 > 0 else {
            return nil
        }
        return top.0
    }

    // MARK: - Formatting

    private func msText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return String(value)
    }

    private func fpsText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: "%.0f", value)
    }
}
