import Testing
@testable import itermplex

@Suite struct VTSynthesizerTests {
    private func frame(_ lines: [[ScreenCell]], cols: Int, rows: Int,
                       cx: Int = 0, cy: Int = 0) -> ScreenFrame {
        ScreenFrame(session: "s", cols: cols, rows: rows, cursorX: cx, cursorY: cy, lines: lines)
    }

    @Test func firstRenderReportsResizeAndRedrawsFullScreen() {
        let s = VTSynthesizer()
        let out = s.render(frame([[ScreenCell(ch: "h", fg: -1, bg: -1, bold: false),
                                    ScreenCell(ch: "i", fg: -1, bg: -1, bold: false)]],
                                 cols: 2, rows: 1, cx: 2, cy: 0))
        #expect(out.resize == VTResize(cols: 2, rows: 1))
        // Reset + clear + home, "hi", then cursor to row 1 col 3 (1-based).
        #expect(out.vt == "\u{1B}[0m\u{1B}[2J\u{1B}[H\u{1B}[39;49mhi\u{1B}[1;3H")
    }

    @Test func emitsPaletteColorAndBoldSGR() {
        let s = VTSynthesizer()
        let out = s.render(frame([[ScreenCell(ch: "X", fg: 15, bg: 4, bold: true)]],
                                 cols: 1, rows: 1, cx: 0, cy: 0))
        #expect(out.vt.contains("\u{1B}[1;38;5;15;48;5;4mX"))
    }

    @Test func secondRenderSameSizeDoesNotResize() {
        let s = VTSynthesizer()
        _ = s.render(frame([[ScreenCell(ch: "a", fg: -1, bg: -1, bold: false)]], cols: 1, rows: 1))
        let out = s.render(frame([[ScreenCell(ch: "b", fg: -1, bg: -1, bold: false)]], cols: 1, rows: 1))
        #expect(out.resize == nil)
    }
}
