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
                case .failure: self.handleDrop(failureStatus: (task?.response as? HTTPURLResponse)?.statusCode)
                }
            }
        }
    }

    /// Pure decision of what state a dropped connection should land in, given the
    /// HTTP status of the WebSocket handshake response (if any). A 401 means the
    /// server rejected the token, which is unrecoverable without user action; any
    /// other status (or none, e.g. a plain connectivity failure) is treated as a
    /// transient drop worth retrying.
    static func connectionState(forFailureStatus status: Int?) -> RemoteConnectionState {
        status == 401 ? .unauthorized : .unreachable
    }

    private func handleDrop(failureStatus: Int?) {
        socket = nil
        guard running else { return }
        let newState = Self.connectionState(forFailureStatus: failureStatus)
        state = newState
        guard newState == .unreachable else { return }
        // Reconnect after a short backoff. Not scheduled for `.unauthorized`: a bad
        // token won't fix itself, so retrying would just spin forever.
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, self.running else { return }
            self.connect()
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
