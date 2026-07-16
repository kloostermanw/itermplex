import Testing
@testable import itermplex

@Suite struct ProcessStateTests {
    @Test func dotMapping() {
        #expect(processDot(for: .running) == ProcessDot(fill: .filled, color: .green))
        #expect(processDot(for: .orphaned) == ProcessDot(fill: .filled, color: .green))
        #expect(processDot(for: .finished) == ProcessDot(fill: .open, color: .green))
        #expect(processDot(for: .failed(3)) == ProcessDot(fill: .open, color: .red))
        #expect(processDot(for: .idle) == ProcessDot(fill: .open, color: .gray))
        #expect(processDot(for: .starting) == ProcessDot(fill: .open, color: .gray))
        #expect(processDot(for: .stopping) == ProcessDot(fill: .filled, color: .green))
    }
}
