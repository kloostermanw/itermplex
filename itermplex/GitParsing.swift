import Foundation

enum GitParsing {
    /// The integer value of the maximal run of trailing digits in the branch
    /// name, or nil if the branch does not end in a digit.
    static func issueNumber(fromBranch branch: String) -> Int? {
        var reversedDigits = ""
        for character in branch.reversed() {
            if character.isNumber {
                reversedDigits.append(character)
            } else {
                break
            }
        }
        guard !reversedDigits.isEmpty else { return nil }
        return Int(String(reversedDigits.reversed()))
    }

    /// Parses `git rev-list --left-right --count` output ("behind<ws>ahead").
    static func aheadBehind(fromRevListOutput output: String) -> (behind: Int, ahead: Int)? {
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
            return nil
        }
        return (behind, ahead)
    }

    /// Parses a GitHub origin URL (https or ssh) into owner/repo.
    static func ownerRepo(fromRemoteURL url: String) -> (owner: String, repo: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var path: String
        if let range = trimmed.range(of: "github.com/") {
            path = String(trimmed[range.upperBound...])
        } else if let range = trimmed.range(of: "github.com:") {
            path = String(trimmed[range.upperBound...])
        } else {
            return nil
        }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let components = path.split(separator: "/")
        guard components.count >= 2 else { return nil }
        return (String(components[0]), String(components[1]))
    }
}
