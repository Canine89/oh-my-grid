import Foundation
import ApplicationServices

/// Bounded retries for idempotent AX reads. Writes are never retried by this policy.
enum AXReadPolicy {
    static func read<Value>(request: WindowRequest, deadline: TimeInterval,
                            now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                            operation: (Float) -> (AXError, Value?)) -> Result<Value, WindowFailure> {
        for timeout in [0.5, 1.0] {
            guard !request.isCancelled else { return .failure(.cancelled) }
            let remaining = deadline - now()
            guard remaining > 0.01 else { return .failure(.unresponsive) }
            let (error, value) = operation(Float(min(timeout, remaining)))
            guard !request.isCancelled else { return .failure(.cancelled) }
            if error == .success {
                return value.map { .success($0) } ?? .failure(.noWindow)
            }
            if error != .cannotComplete { return .failure(WindowFailure.fromAX(error)) }
        }
        return .failure(.unresponsive)
    }
}
