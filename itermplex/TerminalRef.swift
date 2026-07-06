import Foundation

struct TerminalRef: Identifiable, Equatable, Codable {
    let id: UUID
    var label: String
    var sessionId: String

    init(id: UUID = UUID(), label: String, sessionId: String) {
        self.id = id
        self.label = label
        self.sessionId = sessionId
    }
}
