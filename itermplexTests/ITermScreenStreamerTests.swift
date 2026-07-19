import Testing
@testable import itermplex

@Suite struct ITermScreenStreamerTests {
    @Test func frameLineProducesResizeThenData() {
        let synth = VTSynthesizer()
        let line = #"{"type":"frame","session":"s","cols":1,"rows":1,"cursor":{"x":0,"y":0},"lines":[[["a",-1,-1,0]]]}"#
        let messages = ITermScreenStreamer.messages(for: line, synthesizer: synth)
        #expect(messages.first == .resize(cols: 1, rows: 1))
        #expect(messages.count == 2)
        if case let .data(vt) = messages[1] { #expect(vt.contains("a")) } else { Issue.record("expected data") }
    }

    @Test func nonFrameLineProducesNoMessages() {
        let synth = VTSynthesizer()
        #expect(ITermScreenStreamer.messages(for: #"{"type":"detached","session":"s"}"#, synthesizer: synth).isEmpty)
    }

    @Test func secondFrameSameSizeHasNoResize() {
        let synth = VTSynthesizer()
        let line = #"{"type":"frame","session":"s","cols":1,"rows":1,"cursor":{"x":0,"y":0},"lines":[[["a",-1,-1,0]]]}"#
        _ = ITermScreenStreamer.messages(for: line, synthesizer: synth)
        let messages = ITermScreenStreamer.messages(for: line, synthesizer: synth)
        #expect(!messages.contains { if case .resize = $0 { return true }; return false })
    }
}
