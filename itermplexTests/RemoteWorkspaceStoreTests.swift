import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct RemoteWorkspaceStoreTests {
    private func store() -> RemoteWorkspaceStore {
        RemoteWorkspaceStore(connection: RemoteConnection(id: UUID(), name: "B", host: "127.0.0.1", port: 1, token: "t"))
    }

    @Test func applyingASnapshotUpdatesWorkspacesAndState() {
        let s = store()
        let wsId = UUID().uuidString
        let text = "{\"type\":\"snapshot\",\"workspaces\":[{\"id\":\"\(wsId)\",\"name\":\"demo\",\"terminals\":[]}]}"
        s.apply(snapshotText: text)
        #expect(s.state == .connected)
        #expect(s.workspaces.projects.first?.name == "demo")
    }

    @Test func applyingGarbageIsIgnored() {
        let s = store()
        s.apply(snapshotText: "not json")
        #expect(s.workspaces.projects.isEmpty)
    }

    @Test func a401FailureStatusIsUnauthorized() {
        #expect(RemoteWorkspaceStore.connectionState(forFailureStatus: 401) == .unauthorized)
    }

    @Test func otherFailureStatusesAreUnreachable() {
        #expect(RemoteWorkspaceStore.connectionState(forFailureStatus: nil) == .unreachable)
        #expect(RemoteWorkspaceStore.connectionState(forFailureStatus: 500) == .unreachable)
        #expect(RemoteWorkspaceStore.connectionState(forFailureStatus: 403) == .unreachable)
    }

    @Test func successStatusesYieldNoActionError() {
        #expect(RemoteWorkspaceStore.actionErrorMessage(status: 200, hadTransportError: false) == nil)
        #expect(RemoteWorkspaceStore.actionErrorMessage(status: 201, hadTransportError: false) == nil)
        #expect(RemoteWorkspaceStore.actionErrorMessage(status: 204, hadTransportError: false) == nil)
    }

    @Test func a404StatusYieldsAnActionErrorMentioningTheStatus() {
        let message = RemoteWorkspaceStore.actionErrorMessage(status: 404, hadTransportError: false)
        #expect(message?.contains("404") == true)
    }

    @Test func aTransportErrorWithNoStatusYieldsAnActionError() {
        #expect(RemoteWorkspaceStore.actionErrorMessage(status: nil, hadTransportError: true) != nil)
    }
}
