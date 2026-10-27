@testable import AppBundle
import Common
import Testing

/// Pins the target resolution errors shared by the commands (cmdResolveTargetOrReportError.swift)
@MainActor
@Suite(.aeroSpaceGlobalState)
struct ResolveTargetTest {
    @Test(arguments: windowIdCommands)
    func invalidWindowIdFlag(command: String, args: String) async {
        let output = await runCmd("\(command) --window-id 9999 \(args)")
        #expect(output == .fail("Invalid <window-id> 9999 passed to --window-id"))
    }

    @Test(arguments: windowIdCommands)
    func invalidWindowIdEnv(command: String, args: String) async {
        let output = await runCmd("\(command) \(args)", windowIdEnv: 9999)
        #expect(output == .fail("Invalid <window-id> 9999 specified in AEROSPACE_WINDOW_ID env variable"))
    }

    @Test(arguments: windowCommands)
    func noWindowIsFocused(command: String, args: String) async {
        let output = await runCmd("\(command) \(args)")
        #expect(output == .fail(command == "close" ? "Empty workspace" : "No window is focused"))
    }
}

/// Commands that need a window, with the rest of their mandatory arguments
nonisolated private let windowCommands: [(String, String)] = [
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
nonisolated private let windowIdCommands: [(String, String)] = windowCommands + [("layout", "tiling"), ("resize", "width +10")]
