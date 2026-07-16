import Testing
import Foundation
@testable import itermplex

@MainActor
@Suite struct PTYProcessLauncherTests {
    let dir = URL(fileURLWithPath: "/tmp")

    @Test func capturesOutputAndZeroExit() async throws {
        let launcher = PTYProcessLauncher()
        var output = ""
        var exit: Int32?
        _ = try launcher.launch(
            command: "printf 'hello\\n'", directory: dir, environment: [:],
            onOutput: { output += $0 },
            onExit: { exit = $0 }
        )
        try await waitUntil { exit != nil }
        #expect(exit == 0)
        #expect(output.contains("hello"))
    }

    @Test func reportsNonZeroExit() async throws {
        let launcher = PTYProcessLauncher()
        var exit: Int32?
        _ = try launcher.launch(
            command: "exit 3", directory: dir, environment: [:],
            onOutput: { _ in },
            onExit: { exit = $0 }
        )
        try await waitUntil { exit != nil }
        #expect(exit == 3)
    }

    @Test func reportsTTYToChild() async throws {
        let launcher = PTYProcessLauncher()
        var output = ""
        var exit: Int32?
        _ = try launcher.launch(
            command: "test -t 1 && echo istty || echo notty", directory: dir, environment: [:],
            onOutput: { output += $0 },
            onExit: { exit = $0 }
        )
        try await waitUntil { exit != nil }
        #expect(output.contains("istty"))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(5)) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout { Issue.record("timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
