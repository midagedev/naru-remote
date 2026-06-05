import AppKit
import Foundation

@MainActor
@main
enum VNCLiveStimulusWindow {
    private static var controller: StimulusController?

    static func main() {
        let options = StimulusOptions.parse(CommandLine.arguments.dropFirst())
        DispatchQueue.main.async { run(options: options) }
        NSApplication.shared.run()
    }

    private static func run(options: StimulusOptions) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let view = StimulusView(frame: NSRect(origin: .zero, size: options.size))
        let window = NSWindow(
            contentRect: NSRect(origin: options.origin, size: options.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        controller = StimulusController(
            app: app,
            window: window,
            view: view,
            frameInterval: options.frameInterval,
            duration: options.duration
        )
        controller?.start()
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

private struct StimulusOptions {
    var duration: TimeInterval
    var frameInterval: TimeInterval
    var size: NSSize
    var origin: NSPoint

    static func parse(_ arguments: ArraySlice<String>) -> StimulusOptions {
        var options = StimulusOptions(
            duration: environmentDuration() ?? 12,
            frameInterval: environmentFrameInterval() ?? 1.0 / 12.0,
            size: NSSize(width: 420, height: 240),
            origin: NSPoint(x: 72, y: 72)
        )
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
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
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            case "--y":
                if let value = value(after: index, in: arguments).flatMap(Double.init) {
                    options.origin.y = value
                }
                index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
            default:
                index = arguments.index(after: index)
            }
        }

        options.frameInterval = min(max(options.frameInterval, 1.0 / 60.0), 1)
        options.size.width = min(max(options.size.width, 160), 960)
        options.size.height = min(max(options.size.height, 120), 720)
        return options
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

    private static func value(after index: ArraySlice<String>.Index, in arguments: ArraySlice<String>) -> String? {
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

private final class StimulusView: NSView {
    private var frameIndex = 0

    override var isFlipped: Bool { true }

    func advance() {
        frameIndex += 1
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
    }
}
