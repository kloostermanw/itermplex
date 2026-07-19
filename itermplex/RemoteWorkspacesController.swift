import Foundation
import Observation

/// Maps persisted `RemoteConnection`s to live `RemoteWorkspaceStore`s: starts a
/// store for each new connection, restarts the store (fresh instance) for any
/// connection whose id was kept but whose details changed, and stops + drops
/// the store for any connection that has been removed. `ContentView` renders
/// one sidebar section per entry in `stores`; `SettingsView` calls `sync()`
/// after any add/edit/remove of a connection.
@MainActor
@Observable
final class RemoteWorkspacesController {
    private let connections: RemoteConnectionsStore
    private(set) var stores: [UUID: RemoteWorkspaceStore] = [:]

    init(connections: RemoteConnectionsStore) { self.connections = connections }

    /// Start stores for new connections, restart stores whose connection
    /// details changed (name/host/port/token, same id), and stop stores for
    /// removed ones. An unchanged connection keeps its existing store
    /// instance untouched.
    func sync() {
        let ids = Set(connections.connections.map(\.id))
        for connection in connections.connections {
            if let existing = stores[connection.id], existing.connection == connection { continue }
            stores[connection.id]?.stop()
            let store = RemoteWorkspaceStore(connection: connection)
            stores[connection.id] = store
            store.start()
        }
        for (id, store) in stores where !ids.contains(id) {
            store.stop(); stores[id] = nil
        }
    }
}
