import AppKit
import Foundation
import VNCLiveBenchmarkKit

@MainActor
@main
enum VNCLiveStimulusWindow {
    private static var controller: NSObject?

    static func main() {
        let app = NSApplication.shared
        let options = StimulusOptions.parse(CommandLine.arguments.dropFirst())
        DispatchQueue.main.async { run(options: options, app: app) }
        // Both animation and text-probe modes rely on the AppKit run loop;
        // their controllers call `app.terminate(nil)` when the probe ends.
        app.run()
    }

    private static func run(options: StimulusOptions, app: NSApplication) {
        switch options.mode {
        case .animation:
            runAnimation(options: options, app: app)
        case .hoverProbe:
            runHoverProbe(options: options, app: app)
        case .textProbe:
            runTextProbe(options: options, app: app)
        }
    }

    private static func runAnimation(options: StimulusOptions, app: NSApplication) {
        let isVisualFreshnessProbe = options.visualFreshnessSidecarPath != nil
        app.setActivationPolicy((options.titledAnimationWindow || isVisualFreshnessProbe) ? .regular : .accessory)
        let view = StimulusView(frame: NSRect(origin: .zero, size: options.size))
        view.configureVisualFreshnessSidecar(path: options.visualFreshnessSidecarPath)
        let window = NSWindow(
            contentRect: NSRect(origin: options.origin, size: options.size),
            styleMask: options.titledAnimationWindow ? [.titled] : [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = options.titledAnimationWindow ? "Naru Video Probe" : ""
        window.level = options.titledAnimationWindow ? .normal : .floating
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = isVisualFreshnessProbe || !options.titledAnimationWindow
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view
        if options.titledAnimationWindow || isVisualFreshnessProbe {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            app.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        if options.titledAnimationWindow || isVisualFreshnessProbe {
            window.orderFrontRegardless()
        }

        let animationController = StimulusController(
            app: app,
            window: window,
            view: view,
            frameInterval: options.frameInterval,
            duration: options.duration
        )
        controller = animationController
        animationController.start()
    }

    private static func runHoverProbe(options: StimulusOptions, app: NSApplication) {
        app.setActivationPolicy(.regular)
        let view = HoverProbeView(frame: NSRect(origin: .zero, size: options.size))
        view.configureVisualFreshnessSidecar(path: options.visualFreshnessSidecarPath)
        let window = HoverProbeWindow(
            contentRect: NSRect(origin: options.origin, size: options.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Naru Hover Probe"
        window.level = .floating
        window.backgroundColor = .black
        window.isOpaque = true
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = view

        let hoverProbeController = HoverProbeController(
            app: app,
            window: window,
            view: view,
            duration: options.duration
        )
        controller = hoverProbeController
        hoverProbeController.start()
    }

    private static func runTextProbe(options: StimulusOptions, app: NSApplication) {
        app.setActivationPolicy(.regular)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: options.size.width, height: options.size.height))
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
        textView.string = ""

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: options.size))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let window = TextProbeWindow(
            contentRect: NSRect(origin: options.origin, size: options.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Naru Text Probe"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = scrollView

        let textProbeController = TextProbeController(
            app: app,
            window: window,
            textView: textView,
            payload: options.textProbePayload,
            resultFilePath: options.resultFilePath,
            duration: options.duration
        )
        controller = textProbeController
        textProbeController.start()
    }
}

@MainActor
private final class StimulusController: NSObject {
    private let app: NSApplication
    private let window: NSWindow
    private let view: StimulusView
    private let frameInterval: TimeInterval
    private let duration: TimeInterval
    private var frameTimer: Timer?
    private var stopTimer: Timer?

    init(
        app: NSApplication,
        window: NSWindow,
        view: StimulusView,
        frameInterval: TimeInterval,
        duration: TimeInterval
    ) {
        self.app = app
        self.window = window
        self.view = view
        self.frameInterval = frameInterval
        self.duration = duration
    }

    func start() {
        view.recordCurrentVisualFreshnessFrame()
        frameTimer = Timer.scheduledTimer(
            timeInterval: frameInterval,
            target: self,
            selector: #selector(advance),
            userInfo: nil,
            repeats: true
        )
        stopTimer = Timer.scheduledTimer(
            timeInterval: duration,
            target: self,
            selector: #selector(stop),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func advance() {
        view.advance()
    }

    @objc private func stop() {
        frameTimer?.invalidate()
        stopTimer?.invalidate()
        window.orderOut(nil)
        app.terminate(nil)
    }
}

@MainActor
private final class TextProbeController: NSObject, NSTextViewDelegate {
    private let app: NSApplication
    private let window: NSWindow
    private let textView: NSTextView
    private let payload: BenchmarkTextKeystrokeProbePayload
    private let resultFilePath: String?
    private let duration: TimeInterval
    private var stopTimer: Timer?
    private var focusTimer: Timer?
    private var didMatch = false

    init(
        app: NSApplication,
        window: NSWindow,
        textView: NSTextView,
        payload: BenchmarkTextKeystrokeProbePayload,
        resultFilePath: String?,
        duration: TimeInterval
    ) {
        self.app = app
        self.window = window
        self.textView = textView
        self.payload = payload
        self.resultFilePath = resultFilePath
        self.duration = duration
    }

    func start() {
        textView.delegate = self
        focus()
        write(BenchmarkTextKeystrokeObservationTargetResult.ready(payload: payload))
        focusTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(refocus),
            userInfo: nil,
            repeats: true
        )
        stopTimer = Timer.scheduledTimer(
            timeInterval: duration,
            target: self,
            selector: #selector(stop),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func refocus() {
        focus()
    }

    private func focus() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        app.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        let result = BenchmarkTextKeystrokeObservationTargetResult.make(
            payload: payload,
            observedText: textView.string
        )
        write(result)
        if result.observationStatus == .matched {
            didMatch = true
            stopTimer?.invalidate()
            stopTimer = Timer.scheduledTimer(
                timeInterval: 0.05,
                target: self,
                selector: #selector(stop),
                userInfo: nil,
                repeats: false
            )
        }
    }

    @objc private func stop() {
        focusTimer?.invalidate()
        stopTimer?.invalidate()
        if !didMatch {
            write(BenchmarkTextKeystrokeObservationTargetResult.make(
                payload: payload,
                observedText: textView.string
            ))
        }
        window.orderOut(nil)
        app.terminate(nil)
    }

    private func write(_ result: BenchmarkTextKeystrokeObservationTargetResult) {
        guard let resultFilePath else {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(result) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: resultFilePath), options: [.atomic])
    }
}

private final class TextProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class HoverProbeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class HoverProbeController: NSObject {
    private let app: NSApplication
    private let window: NSWindow
    private let view: HoverProbeView
    private let duration: TimeInterval
    private var stopTimer: Timer?

    init(app: NSApplication, window: NSWindow, view: HoverProbeView, duration: TimeInterval) {
        self.app = app
        self.window = window
        self.view = view
        self.duration = duration
    }

    func start() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        app.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.recordReadyFrame()
        stopTimer = Timer.scheduledTimer(
            timeInterval: duration,
            target: self,
            selector: #selector(stop),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func stop() {
        stopTimer?.invalidate()
        window.orderOut(nil)
        app.terminate(nil)
    }
}

private struct StimulusOptions {
    var mode: StimulusMode
    var duration: TimeInterval
    var frameInterval: TimeInterval
    var size: NSSize
    var origin: NSPoint
    var textProbePayload: BenchmarkTextKeystrokeProbePayload
    var resultFilePath: String?
    var titledAnimationWindow: Bool
    var visualFreshnessSidecarPath: String?
    var placeAtTopLeft: Bool
    var screenIndex: Int?
    var originXWasSpecified: Bool
    var originYWasSpecified: Bool

    static func parse(_ arguments: ArraySlice<String>) -> StimulusOptions {
        var options = StimulusOptions(
            mode: .animation,
            duration: environmentDuration() ?? 12,
            frameInterval: environmentFrameInterval() ?? 1.0 / 12.0,
            size: NSSize(width: 420, height: 240),
            origin: NSPoint(x: 72, y: 72),
            textProbePayload: .unicodeHangul,
            resultFilePath: nil,
            titledAnimationWindow: false,
            visualFreshnessSidecarPath: ProcessInfo.processInfo.environment[
                BenchmarkVisualFreshnessSidecar.environmentKey
            ],
            placeAtTopLeft: false,
            screenIndex: environmentInteger(BenchmarkStreamShapeStimulusEnvironment.screenIndexKey),
            originXWasSpecified: false,
            originYWasSpecified: false
        )
        if let originX = environmentDouble(BenchmarkStreamShapeStimulusEnvironment.originXKey) {
            options.origin.x = originX
            options.originXWasSpecified = true
        }
        if let originY = environmentDouble(BenchmarkStreamShapeStimulusEnvironment.originYKey) {
            options.origin.y = originY
            options.originYWasSpecified = true
        }
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--text-probe":
                options.mode = .textProbe
                index = arguments.index(after: index)
            case "--hover-probe":
                options.mode = .hoverProbe
                index = arguments.index(after: index)
            case "--titled-animation-window":
                options.titledAnimationWindow = true
                index = arguments.index(after: index)
            case "--top-left":
                options.placeAtTopLeft = true
                index = arguments.index(after: index)
            case "--screen-index":
                if let value = value(after: index, in: arguments).flatMap(Int.init), value >= 0 {
                    options.screenIndex = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--text-probe-payload":
                if let value = value(after: index, in: arguments),
                   let payload = BenchmarkTextKeystrokeProbePayload(rawValue: value) {
                    options.textProbePayload = payload
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--result-file":
                options.resultFilePath = value(after: index, in: arguments)
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--visual-freshness-sidecar":
                options.visualFreshnessSidecarPath = value(after: index, in: arguments)
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--duration":
                if let value = value(after: index, in: arguments).flatMap(TimeInterval.init), value > 0 {
                    options.duration = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--frame-interval":
                if let value = value(after: index, in: arguments).flatMap(TimeInterval.init), value > 0 {
                    options.frameInterval = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--width":
                if let value = value(after: index, in: arguments).flatMap(Double.init), value > 0 {
                    options.size.width = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--height":
                if let value = value(after: index, in: arguments).flatMap(Double.init), value > 0 {
                    options.size.height = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--x":
                if let value = value(after: index, in: arguments).flatMap(Double.init) {
                    options.origin.x = value
                    options.originXWasSpecified = true
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--y":
                if let value = value(after: index, in: arguments).flatMap(Double.init) {
                    options.origin.y = value
                    options.originYWasSpecified = true
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            default:
                index = arguments.index(after: index)
            }
        }

        options.frameInterval = min(max(options.frameInterval, 1.0 / 60.0), 1)
        options.size.width = min(max(options.size.width, 160), 960)
        options.size.height = min(max(options.size.height, 120), 720)
        if options.mode == .textProbe {
            options.size.width = max(options.size.width, 360)
            options.size.height = max(options.size.height, 140)
        }
        if options.placeAtTopLeft, let screenFrame = selectedScreenFrame(index: options.screenIndex) {
            if !options.originXWasSpecified {
                options.origin.x = screenFrame.minX + 72
            }
            if !options.originYWasSpecified {
                options.origin.y = max(
                    screenFrame.minY,
                    screenFrame.maxY - options.size.height - 72
                )
            }
        }
        return options
    }

    private static func selectedScreenFrame(index: Int?) -> NSRect? {
        let screens = NSScreen.screens
        if let index, screens.indices.contains(index) {
            return screens[index].visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
    }

    private static func environmentDuration() -> TimeInterval? {
        guard let value = ProcessInfo.processInfo.environment["NARU_LIVE_STIMULUS_DURATION_SECONDS"] else {
            return nil
        }
        return TimeInterval(value).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func environmentFrameInterval() -> TimeInterval? {
        guard let value = ProcessInfo.processInfo.environment["NARU_LIVE_STIMULUS_FRAME_INTERVAL_SECONDS"] else {
            return nil
        }
        return TimeInterval(value).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func environmentInteger(_ key: String) -> Int? {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            return nil
        }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func environmentDouble(_ key: String) -> Double? {
        guard let value = ProcessInfo.processInfo.environment[key] else {
            return nil
        }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func value(after index: ArraySlice<String>.Index, in arguments: ArraySlice<String>) -> String? {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

private enum StimulusMode {
    case animation
    case hoverProbe
    case textProbe
}

private final class HoverProbeView: NSView {
    private var frameIndex = 0
    private var visualFreshnessSidecarPath: String?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func configureVisualFreshnessSidecar(path: String?) {
        visualFreshnessSidecarPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if visualFreshnessSidecarPath?.isEmpty == true {
            visualFreshnessSidecarPath = nil
        }
    }

    func recordReadyFrame() {
        recordCurrentFrame()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        recordHoverFrame()
    }

    override func mouseMoved(with event: NSEvent) {
        recordHoverFrame()
    }

    private func recordHoverFrame() {
        frameIndex += 1
        recordCurrentFrame()
        needsDisplay = true
    }

    private func recordCurrentFrame() {
        guard let visualFreshnessSidecarPath else {
            return
        }
        BenchmarkVisualFreshnessSidecar.append(sequence: frameIndex, to: visualFreshnessSidecarPath)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        let inset: CGFloat = 24
        let targetRect = bounds.insetBy(dx: inset, dy: inset)
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: targetRect, xRadius: 10, yRadius: 10).fill()

        NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.50, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: targetRect, xRadius: 10, yRadius: 10)
        border.lineWidth = 4
        border.stroke()

        let label = frameIndex == 0 ? "hover target ready" : "hover observed \(frameIndex)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (label as NSString).draw(
            in: NSRect(x: inset + 12, y: inset + 14, width: bounds.width - inset * 2 - 24, height: 30),
            withAttributes: attributes
        )
        drawVisualFreshnessMarker()
    }

    private func drawVisualFreshnessMarker() {
        let cellSize = CGFloat(BenchmarkVisualFreshnessMarker.markerPointCellSize)
        let nibbles = BenchmarkVisualFreshnessMarker.nibbles(for: frameIndex)
        let markerWidth = CGFloat(BenchmarkVisualFreshnessMarker.markerCellCount) * cellSize
        let inset: CGFloat = 12
        let anchors = [
            NSPoint(x: inset, y: inset),
            NSPoint(x: max(inset, bounds.width - markerWidth - inset), y: inset),
            NSPoint(x: inset, y: max(inset, bounds.height - cellSize - inset)),
            NSPoint(
                x: max(inset, bounds.width - markerWidth - inset),
                y: max(inset, bounds.height - cellSize - inset)
            ),
            NSPoint(x: max(inset, bounds.midX - markerWidth / 2), y: inset),
            NSPoint(
                x: max(inset, bounds.midX - markerWidth / 2),
                y: max(inset, bounds.height - cellSize - inset)
            )
        ]
        var drawnOrigins = Set<String>()
        for origin in anchors {
            let clampedOrigin = NSPoint(
                x: min(max(origin.x, inset), max(inset, bounds.width - markerWidth - inset)),
                y: min(max(origin.y, inset), max(inset, bounds.height - cellSize - inset))
            )
            let key = "\(Int(clampedOrigin.x.rounded())):\(Int(clampedOrigin.y.rounded()))"
            guard drawnOrigins.insert(key).inserted else {
                continue
            }
            drawVisualFreshnessMarker(at: clampedOrigin, cellSize: cellSize, nibbles: nibbles)
        }

        drawVisualFreshnessTimestampLabel()
    }

    private func drawVisualFreshnessMarker(
        at origin: NSPoint,
        cellSize: CGFloat,
        nibbles: [Int]
    ) {
        for (index, nibble) in nibbles.enumerated() {
            let color = BenchmarkVisualFreshnessMarker.palette[nibble]
            NSColor(
                calibratedRed: CGFloat(color.red) / 255.0,
                green: CGFloat(color.green) / 255.0,
                blue: CGFloat(color.blue) / 255.0,
                alpha: 1
            ).setFill()
            NSBezierPath(rect: NSRect(
                x: origin.x + CGFloat(index) * cellSize,
                y: origin.y,
                width: cellSize,
                height: cellSize
            )).fill()
        }
    }

    private func drawVisualFreshnessTimestampLabel() {
        NSColor(calibratedWhite: 0, alpha: 0.72).setFill()
        NSBezierPath(rect: NSRect(x: 10, y: 40, width: 300, height: 38)).fill()
        let timestampMilliseconds = BenchmarkVisualFreshnessSidecar.currentUptimeNanoseconds() / 1_000_000
        let text = "seq \(frameIndex)  t \(timestampMilliseconds)ms"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (text as NSString).draw(
            in: NSRect(x: 18, y: 48, width: 284, height: 28),
            withAttributes: attributes
        )
    }
}

private final class StimulusView: NSView {
    private var frameIndex = 0
    private var visualFreshnessSidecarPath: String?

    override var isFlipped: Bool { true }

    func configureVisualFreshnessSidecar(path: String?) {
        visualFreshnessSidecarPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        if visualFreshnessSidecarPath?.isEmpty == true {
            visualFreshnessSidecarPath = nil
        }
    }

    func recordCurrentVisualFreshnessFrame() {
        guard let visualFreshnessSidecarPath else {
            return
        }
        BenchmarkVisualFreshnessSidecar.append(
            sequence: frameIndex,
            to: visualFreshnessSidecarPath
        )
        needsDisplay = true
    }

    func advance() {
        frameIndex += 1
        recordCurrentVisualFreshnessFrame()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.95, green: 0.18, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.62, blue: 0.94, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.26, green: 0.80, blue: 0.38, alpha: 1)
        ]
        let stripeWidth = max(bounds.width / 7, 24)
        let offset = CGFloat((frameIndex * 11) % Int(stripeWidth * CGFloat(colors.count)))

        for column in -2..<(Int(bounds.width / stripeWidth) + 4) {
            let x = CGFloat(column) * stripeWidth + offset - stripeWidth * CGFloat(colors.count)
            colors[abs(column) % colors.count].setFill()
            NSBezierPath(rect: NSRect(x: x, y: 0, width: stripeWidth, height: bounds.height)).fill()
        }

        let pulse = CGFloat((frameIndex % 24) + 1) / 24.0
        NSColor(calibratedWhite: 1, alpha: 0.85).setFill()
        let markerSize = min(bounds.width, bounds.height) * (0.18 + pulse * 0.12)
        NSBezierPath(
            ovalIn: NSRect(
                x: bounds.midX - markerSize / 2,
                y: bounds.midY - markerSize / 2,
                width: markerSize,
                height: markerSize
            )
        ).fill()

        drawVisualFreshnessOverlayIfNeeded()
    }

    private func drawVisualFreshnessOverlayIfNeeded() {
        guard visualFreshnessSidecarPath != nil else {
            return
        }

        let cellSize = CGFloat(BenchmarkVisualFreshnessMarker.markerPointCellSize)
        let nibbles = BenchmarkVisualFreshnessMarker.nibbles(for: frameIndex)
        let markerWidth = CGFloat(BenchmarkVisualFreshnessMarker.markerCellCount) * cellSize
        let inset: CGFloat = 12
        let anchors = [
            NSPoint(x: inset, y: inset),
            NSPoint(x: max(inset, bounds.width - markerWidth - inset), y: inset),
            NSPoint(x: inset, y: max(inset, bounds.height - cellSize - inset)),
            NSPoint(
                x: max(inset, bounds.width - markerWidth - inset),
                y: max(inset, bounds.height - cellSize - inset)
            ),
            NSPoint(x: max(inset, bounds.midX - markerWidth / 2), y: inset)
        ]
        var drawnOrigins = Set<String>()
        for origin in anchors {
            let clampedOrigin = NSPoint(
                x: min(max(origin.x, inset), max(inset, bounds.width - markerWidth - inset)),
                y: min(max(origin.y, inset), max(inset, bounds.height - cellSize - inset))
            )
            let key = "\(Int(clampedOrigin.x.rounded())):\(Int(clampedOrigin.y.rounded()))"
            guard drawnOrigins.insert(key).inserted else {
                continue
            }
            drawVisualFreshnessMarker(at: clampedOrigin, cellSize: cellSize, nibbles: nibbles)
        }

        NSColor(calibratedWhite: 0, alpha: 0.72).setFill()
        NSBezierPath(rect: NSRect(x: 10, y: 40, width: 300, height: 38)).fill()
        let timestampMilliseconds = BenchmarkVisualFreshnessSidecar.currentUptimeNanoseconds() / 1_000_000
        let text = "seq \(frameIndex)  t \(timestampMilliseconds)ms"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (text as NSString).draw(
            in: NSRect(x: 18, y: 48, width: 284, height: 28),
            withAttributes: attributes
        )
    }

    private func drawVisualFreshnessMarker(
        at origin: NSPoint,
        cellSize: CGFloat,
        nibbles: [Int]
    ) {
        for (index, nibble) in nibbles.enumerated() {
            let color = BenchmarkVisualFreshnessMarker.palette[nibble]
            NSColor(
                calibratedRed: CGFloat(color.red) / 255.0,
                green: CGFloat(color.green) / 255.0,
                blue: CGFloat(color.blue) / 255.0,
                alpha: 1
            ).setFill()
            NSBezierPath(rect: NSRect(
                x: origin.x + CGFloat(index) * cellSize,
                y: origin.y,
                width: cellSize,
                height: cellSize
            )).fill()
        }
    }
}
