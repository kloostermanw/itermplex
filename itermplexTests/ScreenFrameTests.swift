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
}
