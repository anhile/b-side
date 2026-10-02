import ServiceManagement
import SwiftUI

struct DiagnosticsSettings: View {
    @EnvironmentObject private var player: PlayerController
    @State private var log: [String] = []

    var body: some View {
        Form {
            Section("Memory: \(player.totalMegabytes, specifier: "%.0f") MB") {
                ForEach(player.processes) { process in
                    LabeledContent("\(process.name) (\(String(process.pid)))") {
                        Text("\(process.megabytes, specifier: "%.0f") MB").monospacedDigit()
                    }
                }
            }
            Section("Event log") {
                ScrollView {
                    Text(log.map(Self.short).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Theme.Size.logHeight)
                HStack {
                    Button("Refresh") { log = EventLog.tail(lines: 40) }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([EventLog.file])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(ThinScrollers())
        .onAppear { log = EventLog.tail(lines: 40) }
    }

    /// `2026-09-30T12:51:57+04:00<TAB>D<TAB>track<TAB>…` becomes `12:51:57  track  …`.
    private static func short(_ line: String) -> String {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return line }
        let time = parts[0].split(separator: "T").last.map { $0.prefix(8) } ?? ""
        return ([String(time)] + parts.dropFirst(2).map(String.init)).joined(separator: "  ")
    }
}
