import Foundation

/// The bytes of a picture from the network, for everyone who shows it. One
/// track's cover is wanted at once by the window, Control Center, the
/// notification and the widget; asking for the same address while it is
/// being fetched joins that fetch instead of making another. What was
/// fetched stays in Net.imageSession's cache, so the next ask, or the next
/// launch, is answered without the network.
///
/// A failed fetch is tried again after a pause and logged once, with the
/// caller's name for it.
enum ImageData {
    @MainActor private static var running: [URL: Task<Data?, Never>] = [:]

    /// The picture's bytes, or nil. `timeout` limits one try; a caller that
    /// sets it wants its own answer in time (the notification waits a few
    /// seconds, not a minute), so it does not join a fetch that may be
    /// slower.
    @MainActor
    static func data(for url: URL, label: String, attempts: Int, timeout: TimeInterval? = nil) async -> Data? {
        if timeout == nil, let joined = running[url] { return await joined.value }
        let task = Task { await fetch(url, label: label, attempts: attempts, timeout: timeout) }
        if timeout == nil { running[url] = task }
        let data = await task.value
        if timeout == nil { running[url] = nil }
        return data
    }

    private static func fetch(_ url: URL, label: String, attempts: Int, timeout: TimeInterval?) async -> Data? {
        var request = URLRequest(url: url)
        if let timeout { request.timeoutInterval = timeout }
        var failure = ""
        for attempt in 0..<attempts {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Tuning.artworkRetryDelay * Double(attempt))) }
            do {
                let (data, response) = try await Net.imageSession.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0 // none for a file: the snapshots' covers
                if status == 200 || url.isFileURL { return data }
                failure = "HTTP \(status), \(data.count) bytes"
            } catch {
                failure = error.localizedDescription
            }
        }
        EventLog.write("error\t\(label): \(failure) (\(url.host ?? "?"))")
        return nil
    }
}
