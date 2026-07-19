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
        // Reset + clear + home, "hi" (bold off, default fg/bg), cursor to row 1 col 3.
        #expect(out.vt == "\u{1B}[0m\u{1B}[2J\u{1B}[H\u{1B}[22;39;49mhi\u{1B}[1;3H")
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

    @Test func unchangedFrameEmitsOnlyCursorPositioning() {
        let s = VTSynthesizer()
        let f = ScreenFrame(session: "s", cols: 1, rows: 2, cursorX: 0, cursorY: 0,
                            lines: [[ScreenCell(ch: "a", fg: -1, bg: -1, bold: false)],
                                    [ScreenCell(ch: "b", fg: -1, bg: -1, bold: false)]])
        _ = s.render(f)                 // first: full redraw
        let out = s.render(f)           // identical: nothing to redraw
        #expect(out.resize == nil)
        #expect(out.vt == "\u{1B}[1;1H")   // just reposition the cursor
    }

    @Test func onlyChangedRowIsRewritten() {
        let s = VTSynthesizer()
        let first = ScreenFrame(session: "s", cols: 1, rows: 2, cursorX: 0, cursorY: 1,
                                lines: [[ScreenCell(ch: "a", fg: -1, bg: -1, bold: false)],
                                        [ScreenCell(ch: "b", fg: -1, bg: -1, bold: false)]])
        _ = s.render(first)
        let second = ScreenFrame(session: "s", cols: 1, rows: 2, cursorX: 0, cursorY: 1,
                                 lines: [[ScreenCell(ch: "a", fg: -1, bg: -1, bold: false)],
                                         [ScreenCell(ch: "c", fg: -1, bg: -1, bold: false)]])
        let out = s.render(second)
        // Move to row 2, reset attrs, clear the line, rewrite it, reposition cursor.
        #expect(out.vt == "\u{1B}[2;1H\u{1B}[m\u{1B}[2K\u{1B}[22;39;49mc\u{1B}[2;1H")
        #expect(!out.vt.contains("\u{1B}[2J"))   // no full clear
    }

    @Test func boldToNonBoldTransitionWithinRowResetsBold() {
        let s = VTSynthesizer()
        let out = s.render(frame([[ScreenCell(ch: "A", fg: -1, bg: -1, bold: true),
                                    ScreenCell(ch: "B", fg: -1, bg: -1, bold: false)]],
                                 cols: 2, rows: 1))
        // The second cell must explicitly turn bold off (SGR 22); otherwise it
        // inherits the bold left active by the first cell.
        #expect(out.vt.contains("\u{1B}[1;39;49mA\u{1B}[22;39;49mB"))
    }

    @Test func changedRowClearDoesNotLeakPriorBackground() {
        let s = VTSynthesizer()
        // Row 0 carries a non-default background, so the last SGR the client
        // holds before the next frame sets bg 4. Row 1 then changes.
        let first = ScreenFrame(session: "s", cols: 1, rows: 2, cursorX: 0, cursorY: 0,
                                lines: [[ScreenCell(ch: "a", fg: -1, bg: 4, bold: false)],
                                        [ScreenCell(ch: "b", fg: -1, bg: -1, bold: false)]])
        _ = s.render(first)
        let second = ScreenFrame(session: "s", cols: 1, rows: 2, cursorX: 0, cursorY: 0,
                                 lines: [[ScreenCell(ch: "a", fg: -1, bg: 4, bold: false)],
                                         [ScreenCell(ch: "c", fg: -1, bg: -1, bold: false)]])
        let out = s.render(second)
        // The clear must be preceded by an attribute reset so the erased cells
        // use the default background, not the leftover bg 4.
        #expect(out.vt.hasPrefix("\u{1B}[2;1H\u{1B}[m\u{1B}[2K"))
    }
}
