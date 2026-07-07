import Foundation

enum TerminalKind: String, Codable {
    case terminal
    case claude
}

struct TerminalRef: Identifiable, Equatable, Codable {
    let id: UUID
    var label: String
    var sessionId: String
    var kind: TerminalKind

    init(id: UUID = UUID(), label: String, sessionId: String, kind: TerminalKind = .terminal) {
        self.id = id
        self.label = label
        self.sessionId = sessionId
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, sessionId, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        kind = try container.decodeIfPresent(TerminalKind.self, forKey: .kind) ?? .terminal
    }
}
