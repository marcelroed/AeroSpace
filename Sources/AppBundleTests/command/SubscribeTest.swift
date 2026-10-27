@testable import AppBundle
import Common
import Foundation
import Network
import Testing

@Suite(.aeroSpaceGlobalState)
struct SubscribeTest {
    @Test(arguments: [
        (["focus-changed", "mode-changed"], .success(SubscribeArgs(events: [.focusChanged, .modeChanged]))),
        (["--no-send-initial", "mode-changed"], .success(SubscribeArgs(events: [.modeChanged], sendInitial: false))),
        (["--all"], .success(SubscribeArgs(events: Set(ServerEventType.allCases)))),
        (["unknown-event"], .failure("Can't parse 'unknown-event'.\nPossible values: \(ServerEventType.unionLiteral)")),
        // RB-14: the parser read 'bogus' twice, and added a bogus "Unknown argument" error
        (["focus-changed", "focus-changed", "bogus"], .failure("Can't parse 'bogus'.\nPossible values: \(ServerEventType.unionLiteral)")),
        (["focus-changed", "focus-changed"], .failure("Duplicate event 'focus-changed'")),
        ([], .failure("Either --all or at least one <event> must be specified")),
        (["--all", "focus-changed"], .failure("--all conflicts with specifying individual events")),
        (["--bogus", "focus-changed"], .failure("Unknown flag '--bogus'")),
    ] as [([String], Result<SubscribeArgs, CmdParseError>)])
    func parse(args: [String], expected: Result<SubscribeArgs, CmdParseError>) {
        var cursor = ArgCursor(args)
        expectEqual(Result { () throws(CmdParseError) in try SubscribeArgs.parse(&cursor) }, expected)
    }

    /// A client gets the answer, then the state when it subscribed, then every change of its events, in order
    @Test
    func clientsGetTheStateThenTheChanges() async throws {
        fake.monitorInfos = [testMonitor, rightTestMonitor] // The refresh that detects window 4 reads them
        updateMonitors(fake.monitorInfos)
        check(testMonitor.setActiveWorkspace(Workspace.get(byName: "a")) && rightTestMonitor.setActiveWorkspace(Workspace.get(byName: "b")))
        setUpTree("h_tiles(3)", workspace: "b")
        setUpTree("h_tiles(*1 2)", workspace: "a")
        armFocusChangedCallbacks() // The setup isn't a change
        let server = try await TestSocketServer.start(.aeroSpace)
        defer { server.stop() }
        let all = try await subscribe(server, ["--all"])
        defer { all.cancel() }
        let workspaces = try await subscribe(server, ["--no-send-initial", "focused-workspace-changed"])
        defer { workspaces.cancel() }

        await expectEvents(all, [
            #"{"_event":"focus-changed","windowId":1,"workspace":"a"}"#,
            #"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"a"}"#,
            #"{"_event":"focused-workspace-changed","prevWorkspace":"a","workspace":"a"}"#,
            #"{"_event":"mode-changed","mode":"main"}"#,
        ])
        await runCmd("focus right")
        await expectEvents(all, [#"{"_event":"focus-changed","windowId":2,"workspace":"a"}"#])
        await runCmd("focus-monitor right")
        await expectEvents(all, [
            #"{"_event":"focus-changed","windowId":3,"workspace":"b"}"#,
            #"{"_event":"focused-workspace-changed","prevWorkspace":"a","workspace":"b"}"#,
            #"{"_event":"focused-monitor-changed","monitorId":2,"workspace":"b"}"#,
        ])
        await runCmd("mode resize")
        await expectEvents(all, [#"{"_event":"mode-changed","mode":"resize"}"#])
        await runCmd("workspace c") // A new workspace opens on the main monitor
        await expectEvents(all, [
            #"{"_event":"focus-changed","workspace":"c"}"#,
            #"{"_event":"focused-workspace-changed","prevWorkspace":"b","workspace":"c"}"#,
            #"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"c"}"#,
        ])
        fake.windows[4] = FakeWindow(app: testApp, rect: nil, title: "Window 4")
        await Reconcile.heavy(.ax("test")) // The new window takes the focus of its empty workspace
        await expectEvents(all, [
            #"{"_event":"window-detected","appBundleId":"bobko.AeroSpace.test-app","appName":"bobko.AeroSpace.test-app","windowId":4,"workspace":"c"}"#,
            #"{"_event":"focus-changed","windowId":4,"workspace":"c"}"#,
        ])

        await expectEvents(workspaces, [
            #"{"_event":"focused-workspace-changed","prevWorkspace":"a","workspace":"b"}"#,
            #"{"_event":"focused-workspace-changed","prevWorkspace":"b","workspace":"c"}"#,
        ], then: .workspace)
    }

    /// The client is registered before its answer: nothing between the two is lost
    @Test
    func clientWithoutTheInitialStateGetsTheEventsRightAfterItsAnswer() async throws {
        let server = try await TestSocketServer.start(.aeroSpace)
        defer { server.stop() }
        let client = try await subscribe(server, ["--no-send-initial", "mode-changed"])
        defer { client.cancel() }
        broadcastEvent(.modeChanged(mode: "resize")) // No suspension since the answer
        await expectEvents(client, [#"{"_event":"mode-changed","mode":"resize"}"#])
    }

    nonisolated enum Leaving { case afterTheAnswer, beforeTheAnswer }

    /// The server forgets a client that disconnects, whenever it does, and keeps serving the others
    @Test(arguments: [.afterTheAnswer, .beforeTheAnswer] as [Leaving])
    func clientsThatLeaveAreForgotten(leaving: Leaving) async throws {
        await expectSubscriptions(0) // The clients of other tests are gone
        let server = try await TestSocketServer.start(.aeroSpace)
        defer { server.stop() }
        let stays = try await subscribe(server, ["--no-send-initial", "mode-changed"])
        defer { stays.cancel() }
        let request = ClientRequest(args: ["subscribe", "--all"], stdin: "", windowId: nil, workspace: nil)
        for _ in 0 ..< 50 {
            switch leaving {
                case .afterTheAnswer: try await server.send(request).1.cancel()
                case .beforeTheAnswer:
                    let connection = NWConnection(to: .unix(path: server.path), using: .tcp)
                    await expectEqual(connection.initConnection().error, nil)
                    await expectEqual(connection.writeAtomic(request).error, nil)
                    connection.cancel()
            }
        }
        await expectSubscriptions(1)
        await expectEvents(stays, [])
    }

    /// A client that stays connected but stops reading is disconnected once its queue overflows, instead of making
    /// AeroSpace hold every event for it. A client that reads gets every event
    @Test
    func clientThatStopsReadingIsDisconnected() async throws {
        await expectSubscriptions(0)
        let server = try await TestSocketServer.start(.aeroSpace)
        defer { server.stop() }
        let stalled = try await subscribe(server, ["--no-send-initial", "mode-changed"])
        defer { stalled.cancel() }
        let reading = try await subscribe(server, ["--no-send-initial", "mode-changed"])
        defer { reading.cancel() }

        // In rounds, so that the reading client's writer keeps up. The stalled client's socket takes a few events, and the
        // rest pile up in its queue, which overflows in one of the last two rounds
        let roundSize = 500
        let mode = String(repeating: "m", count: 200)
        for round in 0 ..< maxQueuedEvents / roundSize + 2 {
            for _ in 0 ..< roundSize { broadcastEvent(.modeChanged(mode: mode)) }
            let received = await readFrames(reading, count: roundSize)
            expectEqual(received, Array(repeating: #"{"_event":"mode-changed","mode":"\#(mode)"}"#, count: roundSize), "round \(round)")
        }
        await expectSubscriptions(1)
        var stalledFrames = 0
        while case .success = await withTimeout(seconds: 5, { await stalled.readFrame() }) { stalledFrames += 1 }
        #expect(stalledFrames < maxQueuedEvents, "\(stalledFrames)")
        await expectEvents(reading, [])
    }
}

/// A `subscribe` client that got the success answer
private func subscribe(_ server: TestSocketServer, _ args: [String]) async throws -> NWConnection {
    let (answer, connection) = try await server.send(ClientRequest(args: ["subscribe"] + args, stdin: "", windowId: nil, workspace: nil))
    expectEqual(answer.exitCode, EXIT_CODE_ZERO, "\(answer)")
    return connection
}

/// An event that a test broadcasts after the events it expects: if it comes next, no other event came
private enum Sentinel {
    case mode, workspace

    var event: ServerEvent {
        switch self {
            case .mode: .modeChanged(mode: "sentinel")
            case .workspace: .workspaceChanged(workspace: "sentinel", prevWorkspace: "sentinel")
        }
    }

    var json: String {
        switch self {
            case .mode: #"{"_event":"mode-changed","mode":"sentinel"}"#
            case .workspace: #"{"_event":"focused-workspace-changed","prevWorkspace":"sentinel","workspace":"sentinel"}"#
        }
    }
}

/// Reads the next events of `client`: `expected`, and nothing else
private func expectEvents(
    _ client: NWConnection,
    _ expected: [String],
    then sentinel: Sentinel = .mode,
    sourceLocation: SourceLocation = #_sourceLocation,
) async {
    broadcastEvent(sentinel.event)
    expectEqual(await readFrames(client, count: expected.count + 1), expected + [sentinel.json], sourceLocation: sourceLocation)
}

/// The next `count` frames of `client`, or fewer and why the read stopped
private func readFrames(_ client: NWConnection, count: Int) async -> [String] {
    // One timeout for all of them: a missing event fails, rather than hangs
    let frames: [String]? = await withTimeout(seconds: 5) {
        var frames: [String] = []
        for _ in 0 ..< count {
            let frame = await client.readFrame()
            guard case .success(let data) = frame else {
                frames.append("no event: \(frame)")
                break
            }
            frames.append(String(decoding: data, as: UTF8.self))
        }
        return frames
    }
    return frames ?? ["no event: a timeout"]
}

/// Waits until `count` clients are subscribed: a client's writer ends a moment after it disconnects
private func expectSubscriptions(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while subscriptions.count != count, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    expectEqual(subscriptions.count, count, sourceLocation: sourceLocation)
}
