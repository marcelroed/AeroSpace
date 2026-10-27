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
            await assertRun("\(command) --window-id 9999 \(args)", exitCode: 2, stdout: [], stderr: ["Invalid <window-id> 9999 passed to --window-id"])
        }
    }

    @Test
    func testInvalidWindowIdEnv() async {
        for (command, args) in windowIdCommands {
            await assertRun("\(command) \(args)", env: .defaultEnv.withWindowId(9999), exitCode: 2, stdout: [], stderr: ["Invalid <window-id> 9999 specified in AEROSPACE_WINDOW_ID env variable"])
        }
    }

    @Test
    func testNoWindowIsFocused() async {
        for (command, args) in windowCommands {
            await assertRun("\(command) \(args)", exitCode: 2, stdout: [], stderr: [command == "close" ? "Empty workspace" : "No window is focused"])
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
