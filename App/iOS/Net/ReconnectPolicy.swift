import Foundation

/// Exponential backoff for reconnects: 1 s, 2 s, 4 s … capped at 30 s, each
/// delay jittered by ±20 % so a fleet of phones does not hammer a Mac that
/// just woke up in lockstep. `reset()` after a successful hello.
struct ReconnectPolicy: Equatable {
    var base: TimeInterval = 1
    var cap: TimeInterval = 30
    var jitter: Double = 0.2
    private(set) var attempt = 0

    /// The un-jittered delay for `attempt` (0-based).
    func baseDelay(attempt: Int) -> TimeInterval {
        min(base * pow(2, Double(max(0, attempt))), cap)
    }

    /// Bounds the jittered delay for `attempt` can fall in.
    func bounds(attempt: Int) -> ClosedRange<TimeInterval> {
        let d = baseDelay(attempt: attempt)
        return (d * (1 - jitter))...(d * (1 + jitter))
    }

    /// Delay for the next attempt, then advances. `random` is injectable so
    /// tests can pin the jitter; it receives a unit range and returns a value in it.
    mutating func nextDelay(random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> TimeInterval {
        let d = baseDelay(attempt: attempt)
        attempt += 1
        let factor = random(-jitter...jitter)
        return d * (1 + min(max(factor, -jitter), jitter))
    }

    mutating func reset() {
        attempt = 0
    }
}
