import Foundation

// MARK: - Wire DTOs
//
// These types are the CLIENT's typed binding to the wire format produced by
// `WorkspaceSerializer` (the server producer) and wrapped by `RemoteServer`'s
// `/control` WebSocket as `{"type":"snapshot","workspaces":[...]}`. Property
// names are chosen so `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`
// maps the serializer's snake_case keys (`session_id`, `has_upstream`,
// `base_ahead`, `issue_url`, ...) onto them without hand-written
// `CodingKeys`. `RemoteWorkspaceDecoderTests` has a round-trip test that
// serializes a live `ProjectStore` through `WorkspaceSerializer` and decodes
// the result back through these DTOs, so a key rename on either side fails a
// test instead of silently breaking the remote client.
//
// Fields the server only ever includes conditionally (`git`, `checks`,
// `base_ahead`/`base_behind`, `issue_*`, `pr_*`, `job_name`) are `Optional`
// here so a snapshot that omits them still decodes. Fields required to
// identify an element (`id` + `name` on a workspace; `id` + `session_id` +
// `label` on a terminal) are non-optional: a missing or malformed value
// throws during decode, and `FailableDecodable` (below) turns that into a
// per-element `nil` so one bad workspace/terminal is dropped without
// aborting the whole snapshot.

/// Envelope for the `/control` WebSocket's snapshot message:
/// `{"type":"snapshot","workspaces":[...]}`.
struct ControlSnapshot: Decodable {
    var type: String?
    var workspaces: [FailableDecodable<WorkspacePayload>]
}

struct WorkspacePayload: Decodable {
    var id: UUID
    var name: String
    var terminals: [FailableDecodable<TerminalPayload>]?
    var git: GitPayload?
}

struct TerminalPayload: Decodable {
    var id: UUID
    var sessionId: String
    var label: String
    var kind: String?
    var runState: String?
    var needsAttention: Bool?
    var jobName: String?
}

struct GitPayload: Decodable {
    var branch: String?
    var ahead: Int?
    var behind: Int?
    var hasUpstream: Bool?
    var baseAhead: Int?
    var baseBehind: Int?
    var issueNumber: Int?
    var prNumber: Int?
    var issueUrl: String?
    var prUrl: String?
    var checks: ChecksPayload?
}

struct ChecksPayload: Decodable {
    var passing: Int?
    var failing: Int?
    var cancelled: Int?
    var skipped: Int?
    var pending: Int?
    var summary: String?
}

/// Decodes to `Base?`, swallowing any decoding error into `nil` instead of
/// letting it propagate. Used for the elements of the `workspaces` and
/// `terminals` arrays so one malformed entry is skipped instead of failing
/// the whole snapshot.
struct FailableDecodable<Base: Decodable>: Decodable {
    let base: Base?

    init(from decoder: Decoder) throws {
        base = try? Base(from: decoder)
    }
}
