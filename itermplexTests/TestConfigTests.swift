import Testing
import Foundation
@testable import itermplex

@Suite struct TestConfigTests {
    @Test func decodesAllFields() throws {
        let json = Data("""
        {
          "command": "php-cs-fixer fix -v --dry-run",
          "env": { "APP_ENV": "testing" },
          "allow_empty_vars": true
        }
        """.utf8)
        let cfg = try JSONDecoder().decode(TestConfig.self, from: json)
        #expect(cfg.command == "php-cs-fixer fix -v --dry-run")
        #expect(cfg.env == ["APP_ENV": "testing"])
        #expect(cfg.allowEmptyVars == true)
    }

    @Test func appliesDefaults() throws {
        let json = Data("""
        { "command": "vendor/bin/phpstan analyse" }
        """.utf8)
        let cfg = try JSONDecoder().decode(TestConfig.self, from: json)
        #expect(cfg.command == "vendor/bin/phpstan analyse")
        #expect(cfg.env == [:])
        #expect(cfg.allowEmptyVars == false)
    }
}
