import Darwin
import Foundation

// WebKit's helper processes are started by launchd, so their parent PID is 1
// and `ps` cannot tie them to this app. The kernel does track which app is
// "responsible" for them. This is the call Activity Monitor relies on; it is
// not in the public SDK headers.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePID(_ pid: pid_t) -> pid_t

struct ProcessInfoRow: Identifiable {
    let pid: pid_t
    let name: String
    let footprintBytes: UInt64
    var id: pid_t { pid }
    var megabytes: Double { Double(footprintBytes) / 1_048_576 }
}

enum ProcessReporter {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("B-Side", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Read by scripts/measure.sh. First line is `variant<TAB>X`, then one
    /// `pid<TAB>name` line per process.
    static let stateFile = directory.appendingPathComponent("processes.tsv")

    /// This app plus the WebKit processes that belong to it.
    static func snapshot() -> [ProcessInfoRow] {
        let me = getpid()
        let rows = [row(pid: me, name: "B-Side")]

        var pids = [pid_t](repeating: 0, count: 8192)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return rows }

        var helpers: [ProcessInfoRow] = []
        for pid in pids.prefix(Int(count)) where pid > 0 && pid != me {
            guard responsiblePID(pid) == me, let name = executableName(pid) else { continue }
            helpers.append(row(pid: pid, name: name.replacingOccurrences(of: "com.apple.WebKit.", with: "")))
        }
        return rows + helpers.sorted { $0.pid < $1.pid }
    }

    static func write(_ rows: [ProcessInfoRow]) {
        let lines = ["variant\t\(Tuning.measurementLabel)"] + rows.map { "\($0.pid)\t\($0.name)" }
        try? (lines.joined(separator: "\n") + "\n").write(to: stateFile, atomically: true, encoding: .utf8)
    }

    private static func row(pid: pid_t, name: String) -> ProcessInfoRow {
        ProcessInfoRow(pid: pid, name: name, footprintBytes: footprint(pid) ?? 0)
    }

    private static func executableName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    /// phys_footprint, the same number Activity Monitor shows as "Memory".
    private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}

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
