import Testing
import Foundation
@testable import itermplex

@Suite struct RemoteAccessTokenTests {
    private func store() -> RemoteAccessToken {
        RemoteAccessToken(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func generatesAndPersistsAStableToken() {
        let token = store()
        let first = token.value
        #expect(!first.isEmpty)
        #expect(token.value == first)   // stable across reads
    }

    @Test func regenerateChangesTheToken() {
        let token = store()
        let old = token.value
        let new = token.regenerate()
        #expect(new != old)
        #expect(token.value == new)
    }

    @Test func matchesOnlyTheCurrentToken() {
        let token = store()
        #expect(token.matches(token.value))
        #expect(!token.matches("wrong"))
        #expect(!token.matches(nil))
    }
}
