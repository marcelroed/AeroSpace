@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct ReloadConfigCommandTest {
    @Test
    func warningsAsErrorsIsAcceptedWithoutEffect() {
        // The Raycast extension runs `reload-config --dry-run --warnings-as-errors`
        expectEqual(parsedCmd("reload-config --dry-run --warnings-as-errors", as: ReloadConfigCommand.self), ReloadConfigCommand(dryRun: true))
    }

    /// `CONFIG` in the message is the config's path. The message is "untouched" before the run
    @Test(arguments: [
        ("", false, true, "", nil),
        ("foo = 1\nbar = 2", false, false, unknownFooAndBar, "Failed to parse 'CONFIG'. 2 error(s)\n\n" + unknownFooAndBar),
        ("foo = 1", true, false, "[ERROR] foo: Unknown top-level key", "untouched"),
    ] as [(String, Bool, Bool, String, String?)])
    func dryRun(toml: String, noGui: Bool, isOk: Bool, stdout: String, message: String?) throws {
        let url = FileManager.default.temporaryDirectory.appending(component: "aerospace-reload-config-test-\(UUID().uuidString).toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        world.ui.messageModel.message = Message(body: "untouched")
        defer { world.ui.messageModel.message = nil }

        let result = reloadConfig(args: ReloadConfigCommand(noGui: noGui, dryRun: true), forceConfigUrl: url)
        expectEqual(result.isOk, isOk)
        expectEqual(result.stdout, stdout)
        expectEqual(world.ui.messageModel.message?.body, message?.replacing("CONFIG", with: url.path))
    }
}

nonisolated private let unknownFooAndBar = "[ERROR] bar: Unknown top-level key\n\n[ERROR] foo: Unknown top-level key"
