import Foundation

actor CheckScheduler {
    private var task: Task<Void, Never>?

    func start(
        interval: TimeInterval,
        initialDelay: TimeInterval = 10,
        operation: @escaping @Sendable () async -> Void
    ) {
        task?.cancel()
        task = Task {
            if initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
            }

            while !Task.isCancelled {
                await operation()
                try? await Task.sleep(for: .seconds(max(interval, 60)))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
