import Darwin
import Foundation

/// Timestamped log of playback events, for the "what broke" column in RESULTS.md.
enum EventLog {
    static let file = ProcessReporter.directory.appendingPathComponent("events.log")

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    /// The end of the log, for Diagnostics.
    static func tail(lines: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 16_384
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(lines)).map(String.init)
    }

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))\t\(Tuning.measurementLabel)\t\(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
