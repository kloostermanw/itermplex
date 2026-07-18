import Foundation

/// Identifies which workspace + process a log window shows.
struct ProcessLogWindowID: Codable, Hashable {
    let projectId: UUID
    let name: String
}
