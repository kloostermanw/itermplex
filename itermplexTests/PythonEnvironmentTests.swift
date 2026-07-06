import Testing
import Foundation
@testable import itermplex

@Suite struct PythonEnvironmentTests {
    @Test func discoverInterpreterReturnsFirstExistingCandidate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("python3")
        FileManager.default.createFile(atPath: exe.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        let env = PythonEnvironment(candidatePaths: ["/no/such/python3", exe.path])
        #expect(env.discoverInterpreter() == exe.path)
    }

    @Test func discoverInterpreterReturnsNilWhenNoneExist() {
        let env = PythonEnvironment(candidatePaths: ["/no/such/python3", "/also/missing"])
        #expect(env.discoverInterpreter() == nil)
    }
}
