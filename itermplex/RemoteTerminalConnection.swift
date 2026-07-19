import Foundation

/// Bridges one remote session's `WS /attach` stream to a byte feed for a
/// terminal view and an input sink back to the server. Mirrors the socket
/// lifecycle hardening in `RemoteWorkspaceStore`: the receive loop is bound to
/// the specific socket instance it was started for (via `task === self.socket`),
/// so a `stop()` followed quickly by a new `start()` can never let a stale
/// receive loop deliver into the new socket or keep looping after teardown.
@MainActor
final class RemoteTerminalConnection {
    private let connection: RemoteConnection
    private let sessionId: String
    private var socket: URLSessionWebSocketTask?
    private var running = false

    /// Called with decoded VT bytes to feed the terminal, and with (cols,rows) on resize.
    var onData: (([UInt8]) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    var onEnded: (() -> Void)?

    init(connection: RemoteConnection, sessionId: String) {
        self.connection = connection
        self.sessionId = sessionId
    }

    func start() {
        guard !running,
              let url = URL(string: "ws://\(connection.host):\(connection.port)/attach?session=\(sessionId)&token=\(connection.token)")
        else { return }
        running = true
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task)
    }

    func stop() {
        running = false
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Forwards keystroke bytes from the terminal view up to the server.
    func send(_ bytes: ArraySlice<UInt8>) {
        guard running else { return }
        let text = String(decoding: bytes, as: UTF8.self)
        guard let data = try? JSONSerialization.data(withJSONObject: ["data": text]),
              let json = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(json)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.running, task === self.socket else { return }
                switch result {
                case let .success(.string(text)):
                    self.handle(text)
                    self.receive(on: task)
                case .success:
                    self.receive(on: task)
                case .failure:
                    self.stop()
                    self.onEnded?()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch obj["type"] as? String {
        case "resize":
            if let cols = obj["cols"] as? Int, let rows = obj["rows"] as? Int { onResize?(cols, rows) }
        case "data":
            if let vt = obj["vt"] as? String { onData?(Array(vt.utf8)) }
        case "ended":
            stop()
            onEnded?()
        default:
            break
        }
    }
}
