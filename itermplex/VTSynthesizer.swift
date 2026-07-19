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

    func render(_ frame: ScreenFrame) -> VTOutput {
        var resize: VTResize? = nil
        if frame.cols != lastCols || frame.rows != lastRows {
            resize = VTResize(cols: frame.cols, rows: frame.rows)
            lastCols = frame.cols
            lastRows = frame.rows
        }
        var vt = "\u{1B}[0m\u{1B}[2J\u{1B}[H"   // reset attrs, clear, home
        for (index, row) in frame.lines.enumerated() {
            vt += Self.renderRow(row)
            if index < frame.lines.count - 1 { vt += "\r\n" }
        }
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
