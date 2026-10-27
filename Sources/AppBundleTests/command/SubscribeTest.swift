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
        await Reconcile.heavy(.ax("test"))
        await expectEvents(all, [
            #"{"_event":"window-detected","appBundleId":"bobko.AeroSpace.test-app","appName":"bobko.AeroSpace.test-app","windowId":4,"workspace":"c"}"#,
        ])

        await expectEvents(workspaces, [
            #"{"_event":"focused-workspace-changed","prevWorkspace":"a","workspace":"b"}"#,
            #"{"_event":"focused-workspace-changed","prevWorkspace":"b","workspace":"c"}"#,
        ])
    }
}

/// A `subscribe` client that got the success answer
private func subscribe(_ server: TestSocketServer, _ args: [String]) async throws -> NWConnection {
    let (answer, connection) = try await server.send(ClientRequest(args: ["subscribe"] + args, stdin: "", windowId: nil, workspace: nil))
    expectEqual(answer.exitCode, EXIT_CODE_ZERO, "\(answer)")
    return connection
}

/// Reads the next events of `client`, as many as expected
private func expectEvents(_ client: NWConnection, _ expected: [String], sourceLocation: SourceLocation = #_sourceLocation) async {
    var events: [String] = []
    for _ in expected {
        let frame = await withTimeout(seconds: 5) { await client.readFrame() } // A missing event fails, rather than hangs
        guard case .success(let data) = frame else {
            events.append("no event: \(frame.map { "\($0)" } ?? "a timeout")")
            break
        }
        events.append(String(decoding: data, as: UTF8.self))
    }
    expectEqual(events, expected, sourceLocation: sourceLocation)
}
