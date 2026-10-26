@testable import AppBundle
import Testing

@MainActor
@Suite
struct LatestTaskSlotTest: AeroSpaceTestSuite {
    @Test
    func testReplaceCancelsThePreviousTask() async {
        let slot = LatestTaskSlot()
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        slot.replace { continuation.yield("first isCancelled: \(Task.isCancelled)") }
        slot.replace { continuation.yield("second isCancelled: \(Task.isCancelled)") }
        var result: [String] = []
        for await event in events.prefix(2) { result.append(event) }
        assertEquals(result.sorted(), ["first isCancelled: true", "second isCancelled: false"])
    }

    @Test
    func testCancel() async {
        let slot = LatestTaskSlot()
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        slot.replace { continuation.yield("isCancelled: \(Task.isCancelled)") }
        slot.cancel()
        var result: [String] = []
        for await event in events.prefix(1) { result.append(event) }
        assertEquals(result, ["isCancelled: true"])
    }
}
