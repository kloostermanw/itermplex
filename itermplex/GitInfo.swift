import Foundation

struct ChecksSummary: Equatable, Sendable {
    var passing: Int
    var failing: Int
    var cancelled: Int
    var skipped: Int
    var pending: Int

    var total: Int { passing + failing + cancelled + skipped + pending }
    var hasFailures: Bool { failing + cancelled > 0 }

    var summaryText: String {
        var parts: [String] = []
        if failing > 0 { parts.append("\(failing) failing") }
        if cancelled > 0 { parts.append("\(cancelled) cancelled") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if passing > 0 { parts.append("\(passing) successfull checks") }
        if pending > 0 { parts.append("\(pending) pending") }
        return parts.joined(separator: ", ")
    }
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
