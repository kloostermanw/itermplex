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
/// Holds the last dimensions so it only reports a resize when they change.
/// This produces a full redraw on every frame; line-level diffing is added in a
/// later task.
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
                    vt += "\u{1B}[\(index + 1);1H\u{1B}[2K"   // go to row, clear it
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
        var codes: [String] = []
        if cell.bold { codes.append("1") }
        codes.append(cell.fg < 0 ? "39" : "38;5;\(cell.fg)")
        codes.append(cell.bg < 0 ? "49" : "48;5;\(cell.bg)")
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }
}
