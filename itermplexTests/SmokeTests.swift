import Testing

@Suite struct SmokeTests {
    @Test func sanity() {
        #expect(1 + 1 == 2)
    }
}
