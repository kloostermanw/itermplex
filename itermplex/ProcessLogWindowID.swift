import Foundation

/// Identifies which workspace + process a log window shows. `isTest` selects the
/// test supervisor instead of the process supervisor, since the two are separate
/// namespaces that may share a name.
struct ProcessLogWindowID: Codable, Hashable {
    let projectId: UUID
    let name: String
    var isTest: Bool = false
}
