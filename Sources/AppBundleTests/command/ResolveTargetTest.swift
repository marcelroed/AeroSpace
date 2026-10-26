@testable import AppBundle
import Common
import Testing

/// Pins the target resolution errors shared by the commands (cmdResolveTargetOrReportError.swift)
@MainActor
@Suite(.aeroSpaceGlobalState)
struct ResolveTargetTest: AeroSpaceTestSuite {
    @Test
    func testInvalidWindowIdFlag() async {
        for (command, args) in windowIdCommands {
            assertEquals(
                await parseCommand("\(command) --window-id 9999 \(args)").cmdOrDie.run(.defaultEnv, .emptyStdin),
                CmdResult(stdout: [], stderr: ["Invalid <window-id> 9999 passed to --window-id"], exitCode: Int32ExitCode(rawValue: 2)),
                additionalMsg: command,
            )
        }
    }

    @Test
    func testInvalidWindowIdEnv() async {
        for (command, args) in windowIdCommands {
            assertEquals(
                await parseCommand("\(command) \(args)").cmdOrDie.run(.defaultEnv.withWindowId(9999), .emptyStdin),
                CmdResult(stdout: [], stderr: ["Invalid <window-id> 9999 specified in AEROSPACE_WINDOW_ID env variable"], exitCode: Int32ExitCode(rawValue: 2)),
                additionalMsg: command,
            )
        }
    }

    @Test
    func testNoWindowIsFocused() async {
        for (command, args) in windowCommands {
            assertEquals(
                await parseCommand("\(command) \(args)").cmdOrDie.run(.defaultEnv, .emptyStdin),
                CmdResult(
                    stdout: [],
                    stderr: [command == "close" ? "Empty workspace" : "No window is focused"],
                    exitCode: Int32ExitCode(rawValue: 2),
                ),
                additionalMsg: command,
            )
        }
    }
}

/// Commands that need a window, with the rest of their mandatory arguments
private let windowCommands: [(String, String)] = [
    ("close", ""),
    ("fullscreen", ""),
    ("join-with", "left"),
    ("macos-native-fullscreen", ""),
    ("macos-native-minimize", ""),
    ("move", "left"),
    ("move-node-to-monitor", "next"),
    ("move-node-to-workspace", "foo"),
    ("split", "horizontal"),
    ("swap", "left"),
]

/// Commands that accept --window-id
private let windowIdCommands: [(String, String)] = windowCommands + [("layout", "tiling"), ("resize", "width +10")]
