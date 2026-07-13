import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MCP
import NIOCore

/// Hosts the itermplex MCP server over a loopback HTTP endpoint.
///
/// Uses the MCP Swift SDK's `StatelessHTTPServerTransport` (plain JSON
/// request/response, no sessions or SSE, which is all itermplex needs since it
/// sends no server-initiated messages) served by a Hummingbird HTTP server
/// bound to `127.0.0.1`. All tool logic lives in `MCPToolRouter`; this type is
/// only the transport/protocol adapter.
///
/// Connect a client with:
/// `claude mcp add --transport http itermplex http://127.0.0.1:<port>/mcp`
@MainActor
final class MCPServerHost {
    static let defaultPort = 7433
    private static let endpointPath = "mcp"
    private static let maxRequestBytes = 4 * 1024 * 1024

    private let router: MCPToolRouter
    private let port: Int
    private var runTask: Task<Void, Never>?

    /// Populated if the server fails to bind or start.
    private(set) var startupError: String?

    init(router: MCPToolRouter, port: Int = MCPServerHost.defaultPort) {
        self.router = router
        self.port = port
    }

    /// Builds the MCP server + transport, wires them to a Hummingbird HTTP
    /// server, and starts serving in a detached task. Returns once the server
    /// task has been launched; it does not block on the run loop.
    func start() async {
        guard runTask == nil else { return }
        do {
            let transport = StatelessHTTPServerTransport(
                // Permissive pipeline: itermplex binds to loopback only, and
                // many MCP HTTP clients omit the Origin header that the default
                // localhost origin validator would otherwise reject.
                validationPipeline: StandardValidationPipeline(validators: [ContentTypeValidator()])
            )
            let server = try await makeServer()
            try await server.start(transport: transport)

            let application = makeApplication(transport: transport)
            runTask = Task {
                do {
                    try await application.runService()
                } catch {
                    await MainActor.run {
                        self.startupError = "MCP server stopped: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            startupError = "MCP server failed to start: \(error.localizedDescription)"
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    // MARK: - MCP server

    private func makeServer() async throws -> Server {
        let router = self.router
        let server = Server(
            name: "itermplex",
            version: "1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            let descriptors = await router.toolDescriptors()
            let tools = descriptors.map { descriptor in
                Tool(
                    name: descriptor.name,
                    description: descriptor.description,
                    inputSchema: Self.toValue(descriptor.inputSchema)
                )
            }
            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = (params.arguments ?? [:]).mapValues(Self.toJSON)
            do {
                let result = try await router.call(params.name, arguments: arguments)
                return CallTool.Result(
                    content: [.text(text: result.encodedString(), annotations: nil, _meta: nil)],
                    isError: false
                )
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return CallTool.Result(
                    content: [.text(text: message, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        return server
    }

    // MARK: - HTTP server

    private func makeApplication(transport: StatelessHTTPServerTransport) -> some ApplicationProtocol {
        let httpRouter = Router()
        let path = Self.endpointPath
        let maxBytes = Self.maxRequestBytes

        httpRouter.on(RouterPath(path), method: .post) { request, _ -> Response in
            let buffer = try await request.body.collect(upTo: maxBytes)
            let bodyData = Data(buffer: buffer)
            var headers: [String: String] = [:]
            for field in request.headers {
                headers[field.name.canonicalName] = field.value
            }
            let mcpRequest = MCP.HTTPRequest(
                method: request.method.rawValue,
                headers: headers,
                body: bodyData.isEmpty ? nil : bodyData,
                path: "/\(path)"
            )
            let mcpResponse = await transport.handleRequest(mcpRequest)

            var responseHeaders = HTTPFields()
            for (name, value) in mcpResponse.headers {
                if let fieldName = HTTPField.Name(name) {
                    responseHeaders[fieldName] = value
                }
            }
            let status = HTTPResponse.Status(code: mcpResponse.statusCode)
            if let data = mcpResponse.bodyData {
                return Response(
                    status: status,
                    headers: responseHeaders,
                    body: ResponseBody(byteBuffer: ByteBuffer(data: data))
                )
            }
            return Response(status: status, headers: responseHeaders)
        }

        return Application(
            router: httpRouter,
            configuration: ApplicationConfiguration(
                address: .hostname("127.0.0.1", port: port),
                serverName: "itermplex"
            ),
            logger: Logger(label: "itermplex.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
        )
    }

    // MARK: - Value conversion

    nonisolated static func toValue(_ json: JSONValue) -> Value {
        switch json {
        case .null: return .null
        case let .bool(value): return .bool(value)
        case let .int(value): return .int(value)
        case let .double(value): return .double(value)
        case let .string(value): return .string(value)
        case let .array(values): return .array(values.map(toValue))
        case let .object(members): return .object(members.mapValues(toValue))
        }
    }

    nonisolated static func toJSON(_ value: Value) -> JSONValue {
        switch value {
        case .null: return .null
        case let .bool(value): return .bool(value)
        case let .int(value): return .int(value)
        case let .double(value): return .double(value)
        case let .string(value): return .string(value)
        case let .data(_, data): return .string(data.base64EncodedString())
        case let .array(values): return .array(values.map(toJSON))
        case let .object(members): return .object(members.mapValues(toJSON))
        }
    }
}
