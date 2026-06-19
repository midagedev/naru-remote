import Foundation

// Outbound input-event delivery for the app model. Serializes pointer and
// key events into a single in-order pipeline with per-event timeout, stale-
// generation cancellation, and success/failure timing callbacks. Extracted
// from `NaruRemoteAppModel.swift` (it never touches the model) so the model
// file stays focused on session/frame lifecycle.

private enum OutboundInputEventError: Error {
    case timedOut
}

private final class OutboundInputEventOperationRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var tasks: [Task<Void, Never>] = []
    private var isFinished = false

    func setContinuation(_ continuation: CheckedContinuation<Void, any Error>) {
        var shouldResume = false
        lock.lock()
        if isFinished {
            shouldResume = true
        } else {
            self.continuation = continuation
        }
        lock.unlock()

        if shouldResume {
            continuation.resume(throwing: CancellationError())
        }
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        var tasksToCancel: [Task<Void, Never>] = []
        lock.lock()
        if isFinished {
            tasksToCancel = tasks
        } else {
            self.tasks = tasks
        }
        lock.unlock()

        for task in tasksToCancel {
            task.cancel()
        }
    }

    func finish(_ result: Result<Void, any Error>) {
        let continuationToResume: CheckedContinuation<Void, any Error>?
        let tasksToCancel: [Task<Void, Never>]

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        continuationToResume = continuation
        continuation = nil
        tasksToCancel = tasks
        tasks = []
        lock.unlock()

        for task in tasksToCancel {
            task.cancel()
        }
        continuationToResume?.resume(with: result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}

final class OutboundInputEventDispatcher: @unchecked Sendable {
    typealias Operation = @Sendable () async throws -> Void
    typealias Validator = @Sendable () async -> Bool
    typealias Recorder = @Sendable (
        _ queueDelayMilliseconds: Int,
        _ operationMilliseconds: Int,
        _ timedOut: Bool
    ) async -> Void

    private let lock = NSLock()
    private let timeout: Duration
    private var generation = UUID()
    private var tail: Task<Void, Never>?

    init(timeout: Duration) {
        self.timeout = timeout
    }

    func cancelAll() {
        let taskToCancel: Task<Void, Never>?
        lock.lock()
        generation = UUID()
        taskToCancel = tail
        tail = nil
        lock.unlock()

        taskToCancel?.cancel()
    }

    func enqueue(
        operation: @escaping Operation,
        validate: @escaping Validator,
        record: @escaping Recorder,
        handleFailure: @escaping Recorder
    ) {
        let enqueuedAt = Date()
        let previous: Task<Void, Never>?
        let eventGeneration: UUID

        lock.lock()
        previous = tail
        eventGeneration = generation
        lock.unlock()

        let task = Task.detached(priority: .userInitiated) { [
            weak self,
            previous,
            enqueuedAt,
            eventGeneration,
            operation,
            validate,
            record,
            handleFailure
        ] in
            await previous?.value
            guard let self,
                  !Task.isCancelled,
                  self.isCurrent(eventGeneration),
                  await validate()
            else {
                return
            }

            let queueDelayMilliseconds = elapsedMilliseconds(since: enqueuedAt)
            let operationStartedAt = Date()
            do {
                try await Self.runOperation(timeout: self.timeout, operation: operation)
                let operationMilliseconds = elapsedMilliseconds(since: operationStartedAt)
                guard self.isCurrent(eventGeneration) else {
                    return
                }
                await record(queueDelayMilliseconds, operationMilliseconds, false)
            } catch {
                let operationMilliseconds = elapsedMilliseconds(since: operationStartedAt)
                let timedOut: Bool
                if case OutboundInputEventError.timedOut = error {
                    timedOut = true
                } else {
                    timedOut = false
                }
                guard self.invalidateIfCurrent(eventGeneration) else {
                    return
                }
                await handleFailure(queueDelayMilliseconds, operationMilliseconds, timedOut)
            }
        }

        let shouldCancelTask: Bool
        lock.lock()
        if generation == eventGeneration {
            tail = task
            shouldCancelTask = false
        } else {
            shouldCancelTask = true
        }
        lock.unlock()

        if shouldCancelTask {
            task.cancel()
        }
    }

    private func isCurrent(_ eventGeneration: UUID) -> Bool {
        let current: Bool
        lock.lock()
        current = generation == eventGeneration
        lock.unlock()
        return current
    }

    private func invalidateIfCurrent(_ eventGeneration: UUID) -> Bool {
        let taskToCancel: Task<Void, Never>?
        lock.lock()
        guard generation == eventGeneration else {
            lock.unlock()
            return false
        }
        generation = UUID()
        taskToCancel = tail
        tail = nil
        lock.unlock()

        taskToCancel?.cancel()
        return true
    }

    private static func runOperation(
        timeout: Duration,
        operation: @escaping Operation
    ) async throws {
        let race = OutboundInputEventOperationRace()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.setContinuation(continuation)
                let operationTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await operation()
                        race.finish(.success(()))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                let timeoutTask = Task.detached(priority: .userInitiated) {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    operationTask.cancel()
                    race.finish(.failure(OutboundInputEventError.timedOut))
                }
                race.setTasks([operationTask, timeoutTask])
            }
        } onCancel: {
            race.cancel()
        }
    }
}
