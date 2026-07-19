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
    private(set) var connections: [RemoteConnection]
    private let defaults: UserDefaults
    private let key = "itermplex.remote.connections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RemoteConnection].self, from: data) {
            connections = decoded
        } else {
            connections = []
        }
    }

    func add(_ connection: RemoteConnection) { connections.append(connection); persist() }
    func update(_ connection: RemoteConnection) {
        if let i = connections.firstIndex(where: { $0.id == connection.id }) { connections[i] = connection; persist() }
    }
    func remove(id: UUID) { connections.removeAll { $0.id == id }; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(connections) { defaults.set(data, forKey: key) }
    }
}
