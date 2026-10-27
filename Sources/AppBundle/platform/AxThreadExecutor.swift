import Common
import Foundation
import Synchronization

/// The serial executor of one ``AxApp``: a dedicated thread that runs a CFRunLoop. The app's AXObserver sources fire on
/// the same run loop, so the observer callbacks run on the thread that runs the actor's jobs.
/// - Awaited jobs and `enqueueRaw` posts share one FIFO queue. Priority is ignored on purpose.
/// - A version-0 run loop source drains the queue, so the thread services other sources (AX observers) between jobs.
nonisolated final class AxThreadExecutor: SerialExecutor, @unchecked Sendable {
    private enum Item {
        case job(UnownedJob)
        case raw(@Sendable () -> Void)
        case stop
    }

    private let threadName: String
    private let queue: Mutex<[Item]> = Mutex([])
    // Written once on the executor's thread before `init` returns (the semaphore orders it), read-only afterwards
    private var runLoop: CFRunLoop? = nil
    private var source: CFRunLoopSource? = nil
    private var threadId: UInt64 = 0
    private var isDraining = false // Only touched on the executor's thread

    init(threadName: String) {
        self.threadName = threadName
        let isReady = DispatchSemaphore(value: 0)
        let thread = Thread { @Sendable [self] in
            threadId = currentThreadId()
            let runLoop = CFRunLoopGetCurrent()
            var context = unsafe CFRunLoopSourceContext()
            unsafe context.info = Unmanaged.passUnretained(self).toOpaque() // The thread retains self until the run loop stops
            unsafe context.perform = { info in
                guard let info = unsafe info else { return }
                unsafe Unmanaged<AxThreadExecutor>.fromOpaque(info).takeUnretainedValue().drain()
            }
            let source = unsafe CFRunLoopSourceCreate(nil, 0, &context)
            self.runLoop = runLoop
            self.source = source
            // .commonModes: a job still runs while something on this thread runs the loop in another mode (see drain())
            CFRunLoopAddSource(runLoop, source, .commonModes)
            isReady.signal()
            CFRunLoopRun() // Returns after the .stop item
            CFRunLoopSourceInvalidate(source)
        }
        thread.name = threadName
        thread.start()
        isReady.wait()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        push(.job(UnownedJob(job)))
    }

    /// Runs `body` on the executor's thread, in FIFO order with every other job and post
    func enqueueRaw(_ body: @escaping @Sendable () -> Void) {
        push(.raw(body))
    }

    /// Stops the run loop after everything enqueued before, and the thread exits. Only `AxApp`'s isolated deinit calls it,
    /// so nothing can enqueue after it: nothing references the actor anymore. A job enqueued later would never run
    func shutdown() {
        push(.stop)
    }

    private func push(_ item: Item) {
        let wasEmpty = queue.withLock { queue in
            defer { queue.append(item) }
            return queue.isEmpty
        }
        // Signal only on the empty -> non-empty edge: whenever the queue isn't empty, a signal is pending or a drain is running
        if wasEmpty, let source, let runLoop {
            CFRunLoopSourceSignal(source)
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func drain() {
        // If a job spins the run loop (nothing should: an observer callback would enter the actor in the middle of the
        // job, undetected), the other jobs wait until it ends
        if isDraining { return }
        isDraining = true
        defer { isDraining = false }
        while true {
            let batch: [Item] = queue.withLock { queue in
                defer { queue = [] }
                return queue
            }
            if batch.isEmpty { return }
            for item in batch {
                switch item {
                    case .job(let job): unsafe job.runSynchronously(on: asUnownedSerialExecutor())
                    case .raw(let body): body()
                    case .stop: CFRunLoopStop(CFRunLoopGetCurrent())
                }
            }
        }
    }

    var isCurrentThread: Bool { currentThreadId() == threadId }

    // The runtime asks these when `assumeIsolated` runs outside a job of this executor (raw posts, observer callbacks),
    // which traps without them. Being on the thread means being isolated: every job runs on this thread, and drains
    // never nest
    func isIsolatingCurrentContext() -> Bool? { isCurrentThread }

    func checkIsolated() {
        precondition(isCurrentThread, "Expected to run on \(threadName)")
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        unsafe UnownedSerialExecutor(ordinary: self)
    }
}
