@testable import AppBundle
import Testing

@Suite
struct LatestTaskSlotTest {
    @Test
    func testReplaceCancelsThePreviousTask() async {
        let slot = LatestTaskSlot()
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        slot.replace { continuation.yield("first isCancelled: \(Task.isCancelled)") }
        slot.replace { continuation.yield("second isCancelled: \(Task.isCancelled)") }
        var result: [String] = []
        for await event in events.prefix(2) { result.append(event) }
        expectEqual(result.sorted(), ["first isCancelled: true", "second isCancelled: false"])
    }

    @Test
    func testCancel() async {
        let slot = LatestTaskSlot()
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        slot.replace { continuation.yield("isCancelled: \(Task.isCancelled)") }
        slot.cancel()
        var result: [String] = []
        for await event in events.prefix(1) { result.append(event) }
        expectEqual(result, ["isCancelled: true"])
    }

    @Test
    func testIsIdleOnceTheCurrentTaskReturns() async {
        let slot = LatestTaskSlot()
        #expect(slot.isIdle)
        let (first, second) = (Gate(), Gate())
        var hasFirstReturned = false
        slot.replace {
            await first.wait() // Not cancellable: it runs on after the replacement
            hasFirstReturned = true
        }
        await first.untilWaiting()
        slot.replace { await second.wait() }

        first.open()
        for _ in 0 ..< 100 where !hasFirstReturned { await Task.yield() }
        #expect(hasFirstReturned)
        #expect(!slot.isIdle) // The replaced task returned, the current one runs

        second.open()
        for _ in 0 ..< 100 where !slot.isIdle { await Task.yield() }
        #expect(slot.isIdle)
    }
}
