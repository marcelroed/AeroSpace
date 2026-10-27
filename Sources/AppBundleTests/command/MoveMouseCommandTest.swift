@testable import AppBundle
import AppKit
import Common
import Testing

/// GenericParseErrorTest has the parse errors
@Suite(.aeroSpaceGlobalState)
struct MoveMouseCommandTest {
    @Test(arguments: [
        ("move-mouse window-lazy-center", .windowLazyCenter),
        ("move-mouse window-force-center", .windowForceCenter),
        ("move-mouse monitor-lazy-center", .monitorLazyCenter),
        ("move-mouse --fail-if-noop monitor-lazy-center", .monitorLazyCenter),
        ("move-mouse monitor-force-center", .monitorForceCenter),
    ] as [(String, MoveMouseCommand.MouseTarget)])
    func parse(raw: String, expected: MoveMouseCommand.MouseTarget) {
        expectEqual(parsedCmd(raw, as: MoveMouseCommand.self)?.mouseTarget, expected)
    }

    /// Tiles 1 and 2 split the monitor (0, 0, 1920, 1080) in two. Floating window 3 is at (100, 100, 400, 300): the
    /// layout gives a floating window no rect, so the command asks the platform for it
    @Test(arguments: mouseMoves)
    func run(_ row: MouseMove) async {
        setUpTree("h_tiles(1 2) floating(3)")
        testWindow(3).rect = rect(100, 100, 400, 300)
        focus.workspace.layoutWorkspace()
        check(testWindow(row.focused).focusWindow())
        fake.mouseLocation = row.mouse

        expectEqual(await runCmd(row.command), row.expected)
        let warps: [PlatformCall] = row.warpTo.map { [.warpMouse($0)] } ?? []
        expectEqual(fake.calls(of: .warpMouse), warps)
    }

    nonisolated struct MouseMove: Sendable, CustomTestStringConvertible {
        let command: String
        let focused: WindowId
        let mouse: CGPoint
        var expected: CmdOutput = .ok
        /// nil: the mouse stays
        let warpTo: CGPoint?

        var testDescription: String { "'\(command)', window \(focused) focused, mouse at (\(mouse.x), \(mouse.y))" }
    }
}

nonisolated private let insideTile1 = CGPoint(x: 100, y: 100)
nonisolated private let onTile2 = CGPoint(x: 1500, y: 500)
nonisolated private let rightOfTheMonitor = CGPoint(x: 2500, y: 500)
nonisolated private let monitorCenter = CGPoint(x: 960, y: 540)
/// The layout makes the tiles 1 pt shorter than the monitor
nonisolated private let tile1Center = CGPoint(x: 480, y: 539.5)

nonisolated private let mouseMoves: [MoveMouseCommandTest.MouseMove] = [
    .init(command: "move-mouse monitor-lazy-center", focused: 1, mouse: insideTile1, expected: alreadyOnTheMonitor, warpTo: nil),
    .init(command: "move-mouse --fail-if-noop monitor-lazy-center", focused: 1, mouse: insideTile1, expected: .fail(), warpTo: nil),
    .init(command: "move-mouse monitor-lazy-center", focused: 1, mouse: rightOfTheMonitor, warpTo: monitorCenter),
    .init(command: "move-mouse monitor-force-center", focused: 1, mouse: insideTile1, warpTo: monitorCenter),
    .init(command: "move-mouse window-lazy-center", focused: 1, mouse: insideTile1, expected: alreadyOnTheWindow, warpTo: nil),
    .init(command: "move-mouse --fail-if-noop window-lazy-center", focused: 1, mouse: insideTile1, expected: .fail(), warpTo: nil),
    .init(command: "move-mouse window-lazy-center", focused: 1, mouse: onTile2, warpTo: tile1Center),
    .init(command: "move-mouse window-force-center", focused: 1, mouse: insideTile1, warpTo: tile1Center),
    .init(command: "move-mouse window-lazy-center", focused: 3, mouse: onTile2, warpTo: CGPoint(x: 300, y: 250)),
]

nonisolated private let alreadyOnTheMonitor = CmdOutput(stderr: ["The mouse already belongs to the monitor. Tip: use --fail-if-noop to exit with non-zero code"])
nonisolated private let alreadyOnTheWindow = CmdOutput(stderr: ["The mouse already belongs to the window. Tip: use --fail-if-noop to exit with non-zero code"])
