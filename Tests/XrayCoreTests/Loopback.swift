import Foundation
import Network

/// Loopback helpers for the lifecycle test. Everything here stays on 127.0.0.1 — the suite
/// is offline by contract.
struct TimedOut: Error {}

/// Races `body` against a deadline; loses to `TimedOut`.
func withTimeout<T: Sendable>(_ seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimedOut()
        }
        guard let result = try await group.next() else { throw TimedOut() }
        group.cancelAll()
        return result
    }
}

/// A TCP connect that resolves once the connection is `.ready` — or throws on failure.
/// Two seconds is generous for loopback.
func connect(port: UInt16) async throws -> NWConnection {
    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    do {
        try await withTimeout(2) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: continuation.resume()
                    case .failed(let error): continuation.resume(throwing: error)
                    default: break
                    }
                }
                connection.start(queue: .global())
            }
        }
    } catch {
        connection.cancel()
        throw error
    }
    return connection
}

/// `runXray` returns before the inbound listens (~350 ms in the spike), so the test polls a
/// connect until the port accepts or `seconds` pass.
func waitForAccept(port: UInt16, seconds: Double) async throws {
    try await withTimeout(seconds) {
        while true {
            do {
                let probe = try await connect(port: port)
                probe.cancel()
                return
            } catch {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

func send(_ text: String, over connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
    }
}

/// Receives until `marker` appears in the accumulated bytes, the peer closes, or the test's
/// outer timeout wins.
func receiveUntil(_ connection: NWConnection, contains marker: String) async throws -> String {
    var buffer = Data()
    let needle = Data(marker.utf8)
    while !buffer.contains(needle), buffer.count < 1 << 20 {
        let chunk: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data ?? Data()) }
            }
        }
        if chunk.isEmpty { break }
        buffer.append(chunk)
    }
    return String(decoding: buffer, as: UTF8.self)
}

/// Answers whatever it receives with one canned response, then closes. Stands in for the
/// far end of a CONNECT tunnel.
final class EchoServer: @unchecked Sendable {
    static let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"

    private let listener: NWListener

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    /// Starts listening on loopback; returns the bound port once the listener is ready.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                connection.send(content: Data(EchoServer.response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func stop() {
        listener.cancel()
    }
}
