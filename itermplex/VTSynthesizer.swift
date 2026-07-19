import Foundation

struct VTResize: Equatable {
    let cols: Int
    let rows: Int
}

struct VTOutput: Equatable {
    let resize: VTResize?
    let vt: String
}

/// Converts iTerm2 screen frames into a terminal (VT) byte stream for xterm.js.
/// Holds the last dimensions and the last rendered grid so it reports a resize
/// only when dimensions change and, on subsequent frames of the same size,
/// rewrites only the rows that differ. The first frame (or a dimension change)
/// forces a full redraw.
///
/// Not thread-safe: one instance per session, called serially.
final class VTSynthesizer {
    private var lastCols: Int?
    private var lastRows: Int?
    private var lastLines: [[ScreenCell]]?

    func render(_ frame: ScreenFrame) -> VTOutput {
        var resize: VTResize? = nil
        let dimsChanged = frame.cols != lastCols || frame.rows != lastRows
        if dimsChanged {
            resize = VTResize(cols: frame.cols, rows: frame.rows)
            lastCols = frame.cols
            lastRows = frame.rows
        }

        var vt: String
        if dimsChanged || lastLines == nil {
            // Full redraw.
            vt = "\u{1B}[0m\u{1B}[2J\u{1B}[H"   // reset attrs, clear, home
            for (index, row) in frame.lines.enumerated() {
                vt += Self.renderRow(row)
                if index < frame.lines.count - 1 { vt += "\r\n" }
            }
        } else {
            // Rewrite only rows that differ from the last frame.
            vt = ""
            let previous = lastLines!
            for (index, row) in frame.lines.enumerated() {
                let old = index < previous.count ? previous[index] : nil
                if old != row {
                    // Reset attributes before clearing so `[2K` erases with the
                    // default background, not whatever SGR the last emission left
                    // active (which would paint the cleared cells).
                    vt += "\u{1B}[\(index + 1);1H\u{1B}[m\u{1B}[2K"   // go to row, reset, clear it
                    vt += Self.renderRow(row)
                }
            }
        }

        lastLines = frame.lines
        // Position cursor (VT is 1-based).
        vt += "\u{1B}[\(frame.cursorY + 1);\(frame.cursorX + 1)H"
        return VTOutput(resize: resize, vt: vt)
    }

    /// Renders one row, emitting an SGR sequence only when a cell's style
    /// differs from the previous cell's, so runs of same-styled cells share one
    /// sequence.
    static func renderRow(_ row: [ScreenCell]) -> String {
        var out = ""
        var lastStyle: (fg: Int, bg: Int, bold: Bool)?
        for cell in row {
            let style = (cell.fg, cell.bg, cell.bold)
            if lastStyle == nil || lastStyle! != style {
                out += sgr(for: cell)
                lastStyle = style
            }
            out += cell.ch
        }
        return out
    }

    static func sgr(for cell: ScreenCell) -> String {
        // Emit the bold state explicitly on every cell (1 on, 22 off), the same
        // way fg/bg always emit 39/49. Otherwise a bold-to-non-bold transition
        // would leave bold active for the rest of the row (39/49 do not clear it).
        var codes: [String] = [cell.bold ? "1" : "22"]
        codes.append(cell.fg < 0 ? "39" : "38;5;\(cell.fg)")
        codes.append(cell.bg < 0 ? "49" : "48;5;\(cell.bg)")
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }
}
