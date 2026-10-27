@testable import AppBundle
import Common
import Foundation
import Testing

@Suite(.aeroSpaceGlobalState)
struct ReloadConfigCommandTest: AeroSpaceTestSuite {
    @Test
    func testErrors() async throws {
        let (url, result, message) = try await dryRunReloadConfig("foo = 1\nbar = 2")
        let errors = "[ERROR] bar: Unknown top-level key\n\n[ERROR] foo: Unknown top-level key"
        #expect(!result.isOk)
        #expect(result.stdout == errors)
        #expect(message?.body == "Failed to parse '\(url.path)'. 2 error(s)\n\n\(errors)")
    }

    @Test
    func testCleanConfig() async throws {
        let (_, result, message) = try await dryRunReloadConfig("")
        #expect(result.isOk)
        #expect(result.stdout.isEmpty)
        #expect(message == nil)
    }

    @Test
    func testNoGui_keepsTheMessage() async throws {
        let (_, result, message) = try await dryRunReloadConfig("foo = 1", noGui: true)
        #expect(!result.isOk)
        #expect(message?.body == "untouched")
    }
}

/// Runs reload-config --dry-run on a config with the `toml` contents.
/// Returns the config URL, the result and the message shown in the GUI (it is "untouched" before the run)
private func dryRunReloadConfig(_ toml: String, noGui: Bool = false) async throws -> (URL, ReloadConfigResult, Message?) {
    let url = FileManager.default.temporaryDirectory.appending(component: "aerospace-reload-config-test-\(UUID().uuidString).toml")
    try toml.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    MessageModel.shared.message = Message(body: "untouched")
    defer { MessageModel.shared.message = nil }
    let args = ReloadConfigCmdArgs(rawArgs: []).copy(\.dryRun, true).copy(\.noGui, noGui)
    let result = await reloadConfig_nonCancellable(args: args, forceConfigUrl: url)
    return (url, result, MessageModel.shared.message)
}
