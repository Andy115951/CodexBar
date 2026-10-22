import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ChatboxHTTPTransportTests {
    @Test
    func `license responses have no persistent cache cookie or credential storage`() {
        let configuration = ChatboxHTTPTransport.configuration()
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 90)
    }

    @Test
    func `isolated requests retain redirect protection and finish their sessions`() async throws {
        let recording = Recording()
        ChatboxSecurityURLProtocol.recording = recording
        defer { ChatboxSecurityURLProtocol.recording = nil }
        let transport = ChatboxHTTPTransport(sessions: ProviderHTTPSessionFactory(
            makeSession: { delegate in
                #expect(delegate is ProviderHTTPRedirectGuardDelegate)
                let configuration = ChatboxHTTPTransport.configuration()
                configuration.protocolClasses = [ChatboxSecurityURLProtocol.self]
                return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            },
            finishSession: { session in
                recording.finish()
                session.finishTasksAndInvalidate()
            }))
        var request = try URLRequest(url: #require(URL(string: "https://chatbox.invalid/license")))
        request.setValue("Bearer synthetic-secret", forHTTPHeaderField: "Authorization")
        for _ in 0..<2 {
            let (data, response) = try await transport.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == "synthetic-license-response")
        }
        #expect(recording.finishedCount == 2)
        #expect(recording.requests.count == 2)
        for sent in recording.requests {
            #expect(sent.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(!sent.httpShouldHandleCookies)
            #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-secret")
        }
        let forbidden = try URLRequest(url: #require(URL(string: "https://other.invalid/capture")))
        let downgrade = try URLRequest(url: #require(URL(string: "http://chatbox.invalid/license")))
        #expect(ProviderHTTPRedirectGuardDelegate.guardedRedirectRequest(
            originalURL: request.url, redirectRequest: forbidden) == nil)
        #expect(ProviderHTTPRedirectGuardDelegate.guardedRedirectRequest(
            originalURL: request.url, redirectRequest: downgrade) == nil)
    }

    fileprivate final class Recording: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedRequests: [URLRequest] = []
        private var finished = 0

        var requests: [URLRequest] {
            self.lock.withLock { self.recordedRequests }
        }

        var finishedCount: Int {
            self.lock.withLock { self.finished }
        }

        func append(_ request: URLRequest) { self.lock.withLock { self.recordedRequests.append(request) } }
        func finish() { self.lock.withLock { self.finished += 1 } }
    }
}

private final class ChatboxSecurityURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var recording: ChatboxHTTPTransportTests.Recording?

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recording?.append(self.request)
        let response = HTTPURLResponse(
            url: self.request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Cache-Control": "public, max-age=3600", "Set-Cookie": "fixture=session; Secure"])!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        self.client?.urlProtocol(self, didLoad: Data("synthetic-license-response".utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
