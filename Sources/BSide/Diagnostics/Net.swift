import Foundation
import Network
import WebKit

/// The one URL session for everything outside the player page: artwork,
/// lyrics, the vibe server, notifications. Debug: `-proxy host:port` sends
/// it and the page through an HTTP CONNECT proxy, for trying the app on a
/// slow or broken network.
enum Net {
    static let session = URLSession(configuration: baseConfiguration())

    /// For pictures, which come from a few hosts, again and again (the
    /// same cover for the window, the strip, Control Center, the
    /// notification, the widget), and which the hosts let be kept for hours:
    /// a cache on disk that outlives the launch, so a library of covers is
    /// not downloaded again at every start. It follows what the host says
    /// about how long a picture stays good.
    static let imageSession: URLSession = {
        let configuration = baseConfiguration()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("B-Side", isDirectory: true).appendingPathComponent("Pictures", isDirectory: true)
        configuration.urlCache = URLCache(memoryCapacity: Tuning.pictureMemoryCacheBytes,
                                          diskCapacity: Tuning.pictureDiskCacheBytes, directory: folder)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    private static func baseConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        if let proxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPSEnable: true, kCFNetworkProxiesHTTPSProxy: proxy.host, kCFNetworkProxiesHTTPSPort: proxy.port,
                kCFNetworkProxiesHTTPEnable: true, kCFNetworkProxiesHTTPProxy: proxy.host, kCFNetworkProxiesHTTPPort: proxy.port,
            ]
        }
        return configuration
    }

    /// The proxy from the launch arguments, or nil.
    static let proxy: (host: String, port: Int)? = {
        guard let text = Settings.defaults.string(forKey: Keys.proxy),
              let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]) else { return nil }
        return (String(text[..<colon]), port)
    }()

    /// Points the page at the proxy too.
    static func apply(to store: WKWebsiteDataStore) {
        guard let proxy, let port = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else { return }
        store.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .init(proxy.host), port: port))]
        EventLog.write("net\tthrough the proxy \(proxy.host):\(proxy.port)")
    }
}
