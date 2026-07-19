import Foundation

/// One cell of a streamed iTerm2 screen grid. `fg`/`bg` are `-1` for the
/// terminal default color, else a `0...255` palette index.
struct ScreenCell: Equatable {
    let ch: String
    let fg: Int
    let bg: Int
    let bold: Bool
}

/// One decoded screen frame emitted by `iterm_streamer.py`: the visible grid of
/// styled cells plus the cursor position.
struct ScreenFrame: Equatable {
    let session: String
    let cols: Int
    let rows: Int
    let cursorX: Int
    let cursorY: Int
    let lines: [[ScreenCell]]

    /// Decodes one NDJSON line into a frame, or nil if the line is not a
    /// well-formed `"type":"frame"` object.
    static func decode(line: String) -> ScreenFrame? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "frame",
              let session = root["session"] as? String,
              let cols = root["cols"] as? Int,
              let rows = root["rows"] as? Int,
              let cursor = root["cursor"] as? [String: Any],
              let cursorX = cursor["x"] as? Int,
              let cursorY = cursor["y"] as? Int,
              let rawLines = root["lines"] as? [[[Any]]] else {
            return nil
        }
        let lines: [[ScreenCell]] = rawLines.map { row in
            row.compactMap { cell in
                guard cell.count == 4,
                      let ch = cell[0] as? String,
                      let fg = cell[1] as? Int,
                      let bg = cell[2] as? Int,
                      let bold = cell[3] as? Int else { return nil }
                return ScreenCell(ch: ch, fg: normalizeColor(fg), bg: normalizeColor(bg), bold: bold != 0)
            }
        }
        return ScreenFrame(session: session, cols: cols, rows: rows,
                           cursorX: cursorX, cursorY: cursorY, lines: lines)
    }

    /// Returns the session id of a `"type":"detached"` line, or nil if the line
    /// is not a detached notification. The daemon emits this when a session ends
    /// or can no longer be streamed.
    static func detachedSession(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "detached",
              let session = root["session"] as? String else {
            return nil
        }
        return session
    }

    /// A color is either the terminal default (-1) or a 0...255 palette index.
    /// Anything else (a bug or protocol drift in the daemon) collapses to the
    /// default rather than flowing into a malformed `38;5;N` SGR sequence.
    private static func normalizeColor(_ value: Int) -> Int {
        (value >= 0 && value <= 255) ? value : -1
    }
}
