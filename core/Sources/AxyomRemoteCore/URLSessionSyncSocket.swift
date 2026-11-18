import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real socket, on URLSession's WebSocket task (iOS; Linux where
/// swift-corelibs-foundation provides it). Used by the app and by the
/// optional live check in Tests (SYNC_LIVE=1), never by the unit tests.
public final class URLSessionSyncSocket: SyncSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    public init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.resume()
    }

    public static let factory: SyncSocketFactory = { url in URLSessionSyncSocket(url: url) }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let s): return s
        case .data(let d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
