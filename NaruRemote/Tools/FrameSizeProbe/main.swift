import Foundation
import NaruRemoteCore

// Quick ServerInit probe: connect to the live VNC server, read the first
// frame, and print framebuffer width/height/name so we can tell whether
// macOS handed the client the console display or a virtual display.

let host = ProcessInfo.processInfo.environment["NARU_PROBE_HOST"] ?? "127.0.0.1"
let portStr = ProcessInfo.processInfo.environment["NARU_PROBE_PORT"] ?? "5900"
let password = ProcessInfo.processInfo.environment["NARU_PROBE_PASSWORD"] ?? ""
let outPNG = ProcessInfo.processInfo.environment["NARU_PROBE_OUT"] ?? "/tmp/naru-frame.png"
let port = UInt16(portStr) ?? 5900
let typePayload = ProcessInfo.processInfo.environment["NARU_PROBE_TYPE"]

let client = RFBNetworkClient()
let credential = RFBConnectionCredential.vncPassword(password)
do {
    let serverInit = try client.connectSession(
        host: host,
        port: port,
        credential: credential,
        timeout: 5
    )
    print("SERVER_INIT width=\(serverInit.width) height=\(serverInit.height) name=\(serverInit.name)")

    if let typePayload {
        // NARU_PROBE_TYPE_AFTER_FRAME=1 — request and receive one framebuffer
        // update before typing, to test whether the server's input-readiness
        // gate is protocol-progress-based rather than time-based.
        if ProcessInfo.processInfo.environment["NARU_PROBE_TYPE_AFTER_FRAME"] == "1",
           let streamingClient = client as? any RFBStreamingClient {
            let warmupPump = RFBFramePump(source: streamingClient)
            _ = try warmupPump.run(
                configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: 10)
            ) { _ in .stop }
            print("WARMUP_FRAME_RECEIVED")
        }
        // ScreensharingAgent initializes its keymap a few seconds after the
        // viewer connects; events sent before that are dropped silently.
        // NARU_PROBE_TYPE_DELAY (seconds, default 0) lets us probe that window.
        if let delayStr = ProcessInfo.processInfo.environment["NARU_PROBE_TYPE_DELAY"],
           let delay = Double(delayStr), delay > 0 {
            print("TYPE_DELAY \(delay)s")
            usleep(UInt32(delay * 1_000_000))
        }
        // Login-through helper: emit the string as per-scalar keysym
        // down/up pairs, then a Return. Used to type the console user's
        // password into the off-console loginwindow VNC session hands
        // to anonymous viewers.
        let keyEventClient = client as? any RFBKeyEventClient
        let sendSemaphore = DispatchSemaphore(value: 0)
        func sendKey(_ keysym: UInt32, isDown: Bool) {
            // Task.detached, not Task: top-level code is @MainActor, so a
            // plain Task would inherit the main actor and deadlock against
            // the semaphore wait below.
            Task.detached {
                try? await keyEventClient?.sendKeyEvent(keysym: keysym, isDown: isDown)
                sendSemaphore.signal()
            }
            sendSemaphore.wait()
        }
        // NARU_PROBE_TYPE_INTERVAL_MS (default 40) — inter-event gap, lets us
        // measure whether back-to-back keysym bursts lose events server-side.
        let intervalMs = ProcessInfo.processInfo.environment["NARU_PROBE_TYPE_INTERVAL_MS"]
            .flatMap(UInt32.init) ?? 40
        let gap = intervalMs * 1_000
        for scalar in typePayload.unicodeScalars {
            guard let keysym = TextKeystrokeTranscoder.keysym(for: scalar) else { continue }
            sendKey(keysym, isDown: true)
            if gap > 0 { usleep(gap) }
            sendKey(keysym, isDown: false)
            if gap > 0 { usleep(gap) }
        }
        sendKey(KeysymMapping.keysym(for: .return), isDown: true)
        usleep(40_000)
        sendKey(KeysymMapping.keysym(for: .return), isDown: false)
        print("TYPED_PAYLOAD length=\(typePayload.count) +Return")
        sleep(6)
    }
    if let streamingClient = client as? any RFBStreamingClient {
        let pump = RFBFramePump(source: streamingClient)
        var firstFrame: RFBFramePumpFrame?
        _ = try pump.run(
            configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: 10)
        ) { frame in
            firstFrame = frame
            return .stop
        }
        guard let framebuffer = firstFrame?.framebuffer else {
            print("FRAME_FETCH_ERROR no-frame")
            exit(0)
        }
        // Downsampled ASCII luminance map of the remote frame — lets a
        // text agent "see" whether the VNC view shows the busy console
        // desktop or an empty virtual-login desktop.
        let cols = 96
        let rows = max(1, framebuffer.height * cols / framebuffer.width / 2)
        var map = ""
        let ramp = Array(" .:-=+*#%@")
        for row in 0..<rows {
            for col in 0..<cols {
                let x = col * framebuffer.width / cols
                let y = row * framebuffer.height / rows
                guard let c = framebuffer[x, y] else { continue }
                let lum = (Int(c.red) + Int(c.green) + Int(c.blue)) / 3
                let idx = min(ramp.count - 1, lum * ramp.count / 256)
                map.append(ramp[idx])
            }
            map.append("\n")
        }
        print("FRAME_LUMA_MAP_BEGIN")
        print(map)
        print("FRAME_LUMA_MAP_END")
    }
    exit(0)
} catch {
    print("CONNECT_ERROR \(error)")
    exit(1)
}
