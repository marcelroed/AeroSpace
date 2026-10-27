@testable import AppBundle
import Common
import Foundation
import Testing

@MainActor
@Suite(.aeroSpaceGlobalState)
struct ReloadConfigCommandTest: AeroSpaceTestSuite {
    @Test
    func testErrorsAndWarnings() async throws {
        let (url, result, message) = try await dryRunReloadConfig("foo = 1")
        let error = "[ERROR] foo: Unknown top-level key"
        assertEquals(result.isOk, false)
        assertEquals(result.stdout, error)
        assertEquals(result.stderr, outdatedVersionWarning)
        assertEquals(
            message?.body,
            "Failed to parse '\(url.path)'. 1 error(s). 1 warning(s)\n\n\(error)\n\n\(outdatedVersionWarning)",
        )
        assertEquals(message?.containsWarnings, true)
    }

    @Test
    func testErrorsWithoutWarnings() async throws {
        let (url, result, message) = try await dryRunReloadConfig("config-version = 2\nfoo = 1\nbar = 2", warningsAsErrors: true)
        let errors = "[ERROR] bar: Unknown top-level key\n\n[ERROR] foo: Unknown top-level key"
        assertEquals(result.isOk, false)
        assertEquals(result.stdout, errors)
        assertEquals(result.stderr, "")
        assertEquals(message?.body, "Failed to parse '\(url.path)'. 2 error(s). 0 warning(s)\n\n\(errors)")
        assertEquals(message?.containsWarnings, false)
    }

    @Test
    func testWarningsAsErrors() async throws {
        let (url, result, message) = try await dryRunReloadConfig("", warningsAsErrors: true)
        assertEquals(result.isOk, false)
        assertEquals(result.stdout, outdatedVersionWarning)
        assertEquals(result.stderr, "")
        assertEquals(
            message?.body,
            "Parsed '\(url.path)' with 1 warning(s). Feel free to close this window.\n\n\(outdatedVersionWarning)",
        )
        assertEquals(message?.containsWarnings, true)
    }

    @Test
    func testWarnings() async throws {
        let (_, result, message) = try await dryRunReloadConfig("")
        assertEquals(result.isOk, true)
        assertEquals(result.stdout, "")
        assertEquals(result.stderr, outdatedVersionWarning)
        assertNil(message)
    }

    @Test
    func testCleanConfig() async throws {
        let (_, result, message) = try await dryRunReloadConfig("config-version = 2", warningsAsErrors: true)
        assertEquals(result.isOk, true)
        assertEquals(result.stdout, "")
        assertEquals(result.stderr, "")
        assertNil(message)
    }

    @Test
    func testNoGui_keepsTheMessage() async throws {
        let (_, result, message) = try await dryRunReloadConfig("foo = 1", noGui: true)
        assertEquals(result.isOk, false)
        assertEquals(message?.body, "untouched")
    }
}

private let outdatedVersionWarning = "[WARNING] The current 'config-version = 1' is outdated. " +
    "Please consider migrating to 'config-version = 2'. " +
    "See https://nikitabobko.github.io/AeroSpace/guide#config-version for the migration guide."

/// Runs reload-config --dry-run on a config with the `toml` contents.
/// Returns the config URL, the result and the message shown in the GUI (it is "untouched" before the run)
@MainActor
private func dryRunReloadConfig(
    _ toml: String,
    warningsAsErrors: Bool = false,
    noGui: Bool = false,
) async throws -> (URL, ReloadConfigResult, Message?) {
    let url = FileManager.default.temporaryDirectory.appending(component: "aerospace-reload-config-test-\(UUID().uuidString).toml")
    try toml.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    MessageModel.shared.message = Message(body: "untouched", containsWarnings: false)
    defer { MessageModel.shared.message = nil }
    let args = ReloadConfigCmdArgs(rawArgs: [])
        .copy(\.dryRun, true)
        .copy(\.warningsAsErrors, warningsAsErrors)
        .copy(\.noGui, noGui)
    let result = await reloadConfig_nonCancellable(args: args, forceConfigUrl: url)
    return (url, result, MessageModel.shared.message)
}
