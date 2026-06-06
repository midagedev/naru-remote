import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum BenchmarkProcessWaiter {
    static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        guard timeout > 0 else {
            return !process.isRunning
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return false
            }
            Thread.sleep(forTimeInterval: min(0.02, remaining))
        }
        return true
    }

    static func terminateAndWait(
        _ process: Process,
        graceTimeout: TimeInterval = 0.5
    ) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        guard !waitForExit(process, timeout: graceTimeout) else {
            return
        }

        forceKill(process)
        _ = waitForExit(process, timeout: graceTimeout)
    }

    private static func forceKill(_ process: Process) {
        #if canImport(Darwin)
        kill(process.processIdentifier, SIGKILL)
        #else
        process.terminate()
        #endif
    }
}
