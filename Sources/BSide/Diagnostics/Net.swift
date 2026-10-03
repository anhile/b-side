import Foundation
import Network
import WebKit

/// The one URL session for everything outside the player page: artwork,
/// lyrics, the vibe server, notifications. Debug: `-proxy host:port` sends
/// it and the page through an HTTP CONNECT proxy, for trying the app on a
/// slow or broken network.
enum Net {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        if let proxy {
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPSEnable: true, kCFNetworkProxiesHTTPSProxy: proxy.host, kCFNetworkProxiesHTTPSPort: proxy.port,
                kCFNetworkProxiesHTTPEnable: true, kCFNetworkProxiesHTTPProxy: proxy.host, kCFNetworkProxiesHTTPPort: proxy.port,
            ]
        }
        return URLSession(configuration: configuration)
    }()

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
