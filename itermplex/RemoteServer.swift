import Foundation
import Hummingbird
import HummingbirdWebSocket
import HTTPTypes
import Logging
import NIOCore

/// LAN-facing HTTP + WebSocket server. Serves the web client, a token-gated
/// session list, and a token-gated per-session terminal socket bridged to
/// `ITermScreenStreamer`. Opt-in and best-effort: startup failures are recorded,
/// never fatal.
@MainActor
final class RemoteServer {
    static let defaultPort = 7434

    private let store: ProjectStore
    private let streamer: ITermScreenStreamer
    private let token: RemoteAccessToken
    private let port: Int
    private var runTask: Task<Void, Never>?

    private(set) var startupError: String?

    init(store: ProjectStore, streamer: ITermScreenStreamer,
         token: RemoteAccessToken, port: Int = RemoteServer.defaultPort) {
        self.store = store
        self.streamer = streamer
        self.token = token
        self.port = port
    }

    func start() async {
        guard runTask == nil else { return }
        let expected = token.value
        let store = self.store
        let streamer = self.streamer

        // HTTP routes.
        let router = Router()
        router.get("/") { _, _ -> Response in
            Self.fileResponse(resource: "remote_index", ext: "html", contentType: "text/html; charset=utf-8")
        }
        router.get("vendor/xterm.js") { _, _ -> Response in
            Self.fileResponse(resource: "xterm", ext: "js", contentType: "application/javascript")
        }
        router.get("vendor/xterm.css") { _, _ -> Response in
            Self.fileResponse(resource: "xterm", ext: "css", contentType: "text/css")
        }
        router.get("api/sessions") { request, _ -> Response in
            guard Self.tokenOK(request, expected: expected) else {
                return Response(status: .unauthorized)
            }
            let data = await MainActor.run { () -> Data in
                let payload = RemoteSessionList.json(projects: store.projects)
                return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            }
            return Response(status: .ok,
                            headers: [.contentType: "application/json"],
                            body: ResponseBody(byteBuffer: ByteBuffer(data: data)))
        }

        // WebSocket route, token checked at upgrade time.
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        wsRouter.ws("attach",
            shouldUpgrade: { request, _ in
                Self.tokenOK(request, expected: expected) ? .upgrade([:]) : .dontUpgrade
            },
            onUpgrade: { inbound, outbound, context in
                guard let session = Self.query(context.request, "session") else { return }
                let sink = WebSocketSink(outbound: outbound)
                // Frames must reach the socket in the order the streamer emits
                // them (a VT byte stream is order critical). Funnel them through
                // one AsyncStream drained by a single sequential writer rather
                // than spawning a Task per message, which would not preserve order.
                let (stream, continuation) = AsyncStream.makeStream(of: RemoteMessage.self)
                streamer.attach(session: session) { message in continuation.yield(message) }
                let writer = Task {
                    for await message in stream { await sink.send(message) }
                }
                do {
                    for try await frame in inbound.messages(maxSize: 1 << 20) {
                        if case let .text(text) = frame,
                           let data = text.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let input = obj["data"] as? String {
                            streamer.send(session: session, text: input)
                        }
                    }
                } catch {}
                streamer.detach(session: session)
                continuation.finish()
                await writer.value
            })

        let application = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
            configuration: ApplicationConfiguration(
                address: .hostname("0.0.0.0", port: port),
                serverName: "itermplex-remote"),
            logger: Logger(label: "itermplex.remote", factory: { _ in SwiftLogNoOpLogHandler() }))

        runTask = Task {
            do { try await application.runService() }
            catch { await MainActor.run { self.startupError = error.localizedDescription } }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    // MARK: - Helpers

    private nonisolated static func tokenOK(_ request: Request, expected: String) -> Bool {
        query(request, "token") == expected
    }

    private nonisolated static func query(_ request: Request, _ name: String) -> String? {
        request.uri.queryParameters[name[...]].map(String.init)
    }

    private nonisolated static func fileResponse(resource: String, ext: String, contentType: String) -> Response {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            return Response(status: .notFound)
        }
        return Response(status: .ok,
                        headers: [.contentType: contentType],
                        body: ResponseBody(byteBuffer: ByteBuffer(data: data)))
    }
}

/// Serializes outbound WebSocket writes and maps `RemoteMessage` to the wire
/// JSON the web client expects.
private actor WebSocketSink {
    private let outbound: WebSocketOutboundWriter
    init(outbound: WebSocketOutboundWriter) { self.outbound = outbound }

    func send(_ message: RemoteMessage) async {
        let object: [String: Any]
        switch message {
        case let .resize(cols, rows): object = ["type": "resize", "cols": cols, "rows": rows]
        case let .data(vt): object = ["type": "data", "vt": vt]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await outbound.write(.text(text))
    }
}
