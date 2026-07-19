import Foundation
import Observation

enum RemoteConnectionState: Equatable { case connecting, connected, unauthorized, unreachable }

@MainActor
@Observable
final class RemoteWorkspaceStore {
    let connection: RemoteConnection
    private(set) var state: RemoteConnectionState = .connecting
    private(set) var workspaces = DecodedRemoteWorkspaces()

    private var socket: URLSessionWebSocketTask?
    private var running = false
    private var reconnectTask: Task<Void, Never>?

    init(connection: RemoteConnection) { self.connection = connection }

    private var baseURL: String { "http://\(connection.host):\(connection.port)" }
    private func wsURL(_ path: String) -> URL? {
        URL(string: "ws://\(connection.host):\(connection.port)/\(path)?token=\(connection.token)")
    }

    func start() {
        guard !running else { return }
        running = true
        connect()
    }

    func stop() {
        running = false
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Pure application of one snapshot message. Sets `.connected` on success.
    func apply(snapshotText: String) {
        guard let data = snapshotText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        workspaces = RemoteWorkspaceDecoder.decode(snapshot: json)
        state = .connected
    }

    private func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        guard running, let url = wsURL("control") else { return }
        state = .connecting
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        receive()
    }

    private func receive() {
        let task = socket
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.running, task === self.socket else { return }
                switch result {
                case let .success(.string(text)): self.apply(snapshotText: text); self.receive()
                case .success: self.receive()
                case .failure: self.handleDrop()
                }
            }
        }
    }

    private func handleDrop() {
        socket = nil
        guard running else { return }
        state = .unreachable
        // Reconnect after a short backoff.
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.running { self.connect() }
        }
    }

    // MARK: - Actions (best effort; failures are ignored, next snapshot reconciles)

    func openTerminal(workspaceId: UUID) { post("api/workspaces/\(workspaceId.uuidString)/terminal") }
    func openClaude(workspaceId: UUID) { post("api/workspaces/\(workspaceId.uuidString)/claude") }
    func restart(sessionId: String) { post("api/sessions/\(sessionId)/restart") }
    func close(sessionId: String) { post("api/sessions/\(sessionId)/close") }

    private func post(_ path: String) {
        guard let url = URL(string: "\(baseURL)/\(path)?token=\(connection.token)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
    }
}
