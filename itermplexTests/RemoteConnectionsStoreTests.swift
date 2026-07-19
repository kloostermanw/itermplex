import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct RemoteConnectionsStoreTests {
    private func store() -> RemoteConnectionsStore {
        RemoteConnectionsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, secretStore: InMemorySecretStore())
    }

    @Test func addUpdateRemoveRoundTrips() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let secretStore = InMemorySecretStore()
        let s = RemoteConnectionsStore(defaults: defaults, secretStore: secretStore)
        var c = RemoteConnection(id: UUID(), name: "B", host: "1.2.3.4", port: 7434, token: "tok")
        s.add(c)
        #expect(s.connections.count == 1)
        c.name = "B2"; s.update(c)
        #expect(s.connections.first?.name == "B2")
        // Persisted: a fresh store from the same defaults + secret store sees it,
        // including the token round-tripping through the secret store.
        let reloaded = RemoteConnectionsStore(defaults: defaults, secretStore: secretStore)
        #expect(reloaded.connections.first?.name == "B2")
        #expect(reloaded.connections.first?.token == "tok")
        s.remove(id: c.id)
        #expect(s.connections.isEmpty)
        #expect(secretStore.secret(for: c.id.uuidString) == nil)
    }
}
