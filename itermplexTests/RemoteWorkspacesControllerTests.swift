import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct RemoteWorkspacesControllerTests {
    private func connectionsStore() -> RemoteConnectionsStore {
        RemoteConnectionsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func connection(id: UUID = UUID(), name: String = "B") -> RemoteConnection {
        RemoteConnection(id: id, name: name, host: "127.0.0.1", port: 1, token: "t")
    }

    @Test func syncStartsAStoreForANewConnection() {
        let connections = connectionsStore()
        let controller = RemoteWorkspacesController(connections: connections)
        let c = connection()
        connections.add(c)

        controller.sync()

        #expect(controller.stores[c.id] != nil)
    }

    @Test func syncAgainWithNoChangesKeepsTheSameStoreInstance() {
        let connections = connectionsStore()
        let controller = RemoteWorkspacesController(connections: connections)
        let c = connection()
        connections.add(c)
        controller.sync()
        let original = controller.stores[c.id]

        controller.sync()

        #expect(controller.stores[c.id] === original)
    }

    @Test func syncAfterEditingAConnectionReplacesTheStore() {
        let connections = connectionsStore()
        let controller = RemoteWorkspacesController(connections: connections)
        var c = connection(name: "B")
        connections.add(c)
        controller.sync()
        let original = controller.stores[c.id]

        c.name = "B renamed"
        connections.update(c)
        controller.sync()

        let replacement = controller.stores[c.id]
        #expect(replacement !== original)
        #expect(replacement?.connection.name == "B renamed")
    }

    @Test func syncAfterRemovingAConnectionDropsItsStore() {
        let connections = connectionsStore()
        let controller = RemoteWorkspacesController(connections: connections)
        let c = connection()
        connections.add(c)
        controller.sync()
        #expect(controller.stores[c.id] != nil)

        connections.remove(id: c.id)
        controller.sync()

        #expect(controller.stores[c.id] == nil)
    }
}
