import Testing
@testable import itermplex

@Suite struct ScreenFrameTests {
    @Test func decodesAFrameWithStyledCells() {
        let line = #"{"type":"frame","session":"s1","cols":2,"rows":1,"cursor":{"x":1,"y":0},"lines":[[["h",15,-1,1],["i",-1,4,0]]]}"#
        let frame = ScreenFrame.decode(line: line)
        #expect(frame == ScreenFrame(
            session: "s1", cols: 2, rows: 1, cursorX: 1, cursorY: 0,
            lines: [[ScreenCell(ch: "h", fg: 15, bg: -1, bold: true),
                     ScreenCell(ch: "i", fg: -1, bg: 4, bold: false)]]))
    }

    @Test func returnsNilForNonFrameLine() {
        #expect(ScreenFrame.decode(line: #"{"type":"detached","session":"s1"}"#) == nil)
        #expect(ScreenFrame.decode(line: "not json") == nil)
    }

    @Test func normalizesOutOfRangePaletteIndicesToDefault() {
        let line = #"{"type":"frame","session":"s1","cols":2,"rows":1,"cursor":{"x":0,"y":0},"lines":[[["a",999,-5,0],["b",255,0,0]]]}"#
        let frame = ScreenFrame.decode(line: line)
        // 999 and -5 are outside -1...255, so they collapse to the default (-1).
        // 255 and 0 are valid and pass through unchanged.
        #expect(frame?.lines == [[ScreenCell(ch: "a", fg: -1, bg: -1, bold: false),
                                   ScreenCell(ch: "b", fg: 255, bg: 0, bold: false)]])
    }

    @Test func detachedSessionParsesOnlyDetachedLines() {
        #expect(ScreenFrame.detachedSession(line: #"{"type":"detached","session":"s9","reason":"gone"}"#) == "s9")
        #expect(ScreenFrame.detachedSession(line: #"{"type":"frame","session":"s9","cols":1,"rows":1,"cursor":{"x":0,"y":0},"lines":[]}"#) == nil)
        #expect(ScreenFrame.detachedSession(line: "not json") == nil)
    }

    @Test func returnsNilWhenARequiredFieldIsMissing() {
        // Missing "cols".
        #expect(ScreenFrame.decode(line: #"{"type":"frame","session":"s1","rows":1,"cursor":{"x":0,"y":0},"lines":[]}"#) == nil)
        // Missing "cursor".
        #expect(ScreenFrame.decode(line: #"{"type":"frame","session":"s1","cols":1,"rows":1,"lines":[]}"#) == nil)
    }
}
