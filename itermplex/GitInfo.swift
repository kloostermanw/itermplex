import Foundation

struct ChecksSummary: Equatable, Sendable {
    var passing: Int
    var failing: Int
    var cancelled: Int
    var skipped: Int
    var pending: Int

    var total: Int { passing + failing + cancelled + skipped + pending }
    var hasFailures: Bool { failing + cancelled > 0 }
}

struct GitInfo: Equatable, Sendable {
    var branch: String
    var behind: Int
    var ahead: Int
    var hasUpstream: Bool
    var baseAhead: Int = 0
    var baseBehind: Int = 0
    var hasBase: Bool = false
    var issueNumber: Int?
    var prNumber: Int?
    var issueURL: URL?
    var prURL: URL?
    var checks: ChecksSummary?
}
