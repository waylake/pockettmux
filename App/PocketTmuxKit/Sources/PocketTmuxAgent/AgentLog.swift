import Foundation
import os

public struct LogEntry: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable { case info, warning, error }

    public let id: UUID
    public let date: Date
    public let level: Level
    public let message: String

    public var line: String {
        let time = Self.formatter.string(from: date)
        return "\(time) [\(level.rawValue)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Ring-buffered agent log, mirrored to the unified log. The Mac app shows
/// it in Settings › Log; pockettmuxd echoes it to stdout.
public final class AgentLog: @unchecked Sendable {
    public let capacity: Int
    public let echoToStandardOutput: Bool
    /// Delivered on the main queue.
    public var onEntry: (@Sendable (LogEntry) -> Void)?

    private let lock = NSLock()
    private var buffer: [LogEntry] = []
    private let logger = Logger(subsystem: "com.waylake.pockettmux", category: "agent")

    public init(capacity: Int = 500, echoToStandardOutput: Bool = false) {
        self.capacity = capacity
        self.echoToStandardOutput = echoToStandardOutput
    }

    public var entries: [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock(); buffer.removeAll(); lock.unlock()
    }

    public func info(_ message: String) { append(.info, message) }
    public func warning(_ message: String) { append(.warning, message) }
    public func error(_ message: String) { append(.error, message) }

    private func append(_ level: LogEntry.Level, _ message: String) {
        let entry = LogEntry(id: UUID(), date: Date(), level: level, message: message)
        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        lock.unlock()
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        if echoToStandardOutput { print(entry.line) }
        if let onEntry {
            DispatchQueue.main.async { onEntry(entry) }
        }
    }
}
