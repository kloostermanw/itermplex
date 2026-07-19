import Foundation
import Observation

struct RemoteConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var token: String
}

@MainActor
@Observable
final class RemoteConnectionsStore {
    /// Metadata persisted to UserDefaults. Deliberately excludes `token`, which is
    /// kept out of plaintext storage and lives in the `SecretStore` instead.
    private struct ConnectionMetadata: Codable {
        let id: UUID
        var name: String
        var host: String
        var port: Int
    }

    private(set) var connections: [RemoteConnection]
    private let defaults: UserDefaults
    private let secretStore: SecretStore
    private let key = "itermplex.remote.connections"

    init(defaults: UserDefaults = .standard, secretStore: SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secretStore = secretStore
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ConnectionMetadata].self, from: data) {
            connections = decoded.map { metadata in
                RemoteConnection(
                    id: metadata.id,
                    name: metadata.name,
                    host: metadata.host,
                    port: metadata.port,
                    token: secretStore.secret(for: metadata.id.uuidString) ?? ""
                )
            }
        } else {
            connections = []
        }
    }

    func add(_ connection: RemoteConnection) {
        connections.append(connection)
        persist()
        secretStore.setSecret(connection.token, for: connection.id.uuidString)
    }

    func update(_ connection: RemoteConnection) {
        guard let i = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[i] = connection
        persist()
        secretStore.setSecret(connection.token, for: connection.id.uuidString)
    }

    func remove(id: UUID) {
        connections.removeAll { $0.id == id }
        persist()
        secretStore.removeSecret(for: id.uuidString)
    }

    private func persist() {
        let metadata = connections.map { ConnectionMetadata(id: $0.id, name: $0.name, host: $0.host, port: $0.port) }
        if let data = try? JSONEncoder().encode(metadata) { defaults.set(data, forKey: key) }
    }
}
