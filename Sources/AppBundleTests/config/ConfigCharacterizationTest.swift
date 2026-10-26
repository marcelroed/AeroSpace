@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigCharacterizationTest: XCTestCase {
    func testImplicitPersistentWorkspaces() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-1 = 'workspace 1'
                alt-shift-2 = 'move-node-to-workspace 2'
                alt-3 = ['workspace 3', 'move-node-to-workspace 4']
                alt-n = 'workspace next'
            [workspace-to-monitor-force-assignment]
                5 = 'main'
                1 = 'secondary'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.persistentWorkspaces.sorted(), ["1", "2", "3", "4", "5"])
    }

    func testImplicitPersistentWorkspacesOrderWithinBinding() {
        let result = parseConfig(
            """
            [mode.main.binding]
                alt-3 = ['move-node-to-workspace 4', 'workspace 3', 'workspace 3']
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(Array(result.config.persistentWorkspaces), ["3", "4"])
    }

    func testNoImplicitPersistentWorkspacesSinceVersion2() {
        let result = parseConfig(
            """
            config-version = 2
            [mode.main.binding]
                alt-1 = 'workspace 1'
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(Array(result.config.persistentWorkspaces), [])
    }
}
