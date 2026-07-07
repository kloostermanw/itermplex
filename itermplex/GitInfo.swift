import Foundation

struct GitInfo: Equatable, Sendable {
    var branch: String
    var behind: Int
    var ahead: Int
    var hasUpstream: Bool
    var issueNumber: Int?
    var prNumber: Int?
    var issueURL: URL?
    var prURL: URL?
}
