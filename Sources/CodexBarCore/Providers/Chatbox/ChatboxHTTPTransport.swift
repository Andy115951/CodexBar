import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// License responses include the key itself. Keep them out of shared disk caches and cookie stores.
struct ChatboxHTTPTransport: ProviderHTTPTransport {
    var sessions = ProviderHTTPSessionFactory(makeSession: { delegate in
        URLSession(configuration: Self.configuration(), delegate: delegate, delegateQueue: nil)
    })

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        #if !os(Linux)
        configuration.waitsForConnectivity = false
        #endif
        return configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        let response = try await self.sessions.response(for: request, delegate: ProviderHTTPRedirectGuardDelegate())
        return (response.data, response.response)
    }
}
