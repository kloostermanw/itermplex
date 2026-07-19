import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct RemoteConnectionsStoreTests {
    private func store() -> RemoteConnectionsStore {
        RemoteConnectionsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func addUpdateRemoveRoundTrips() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let s = RemoteConnectionsStore(defaults: defaults)
        var c = RemoteConnection(id: UUID(), name: "B", host: "1.2.3.4", port: 7434, token: "tok")
        s.add(c)
        #expect(s.connections.count == 1)
        c.name = "B2"; s.update(c)
        #expect(s.connections.first?.name == "B2")
        // Persisted: a fresh store from the same defaults sees it.
        #expect(RemoteConnectionsStore(defaults: defaults).connections.first?.name == "B2")
        s.remove(id: c.id)
        #expect(s.connections.isEmpty)
    }
}
