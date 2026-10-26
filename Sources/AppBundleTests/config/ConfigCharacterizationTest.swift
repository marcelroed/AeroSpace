@testable import AppBundle
import Common
import Testing

@MainActor
@Suite
struct ConfigCharacterizationTest: AeroSpaceTestSuite {
    @Test
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

    @Test
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

    @Test
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

    @Test
    func testDynamicGapValueOfWrongScalarType() {
        let result = parseConfig(
            """
            [gaps]
                inner.vertical = true
                inner.horizontal = '5'
                outer.left = [{ monitor.main = true }, 1]
                outer.right = [{ monitor.main = 1 }, false]
                outer.top = [{ monitor.main = 1 }, '2']
            """,
        )
        assertEquals(result.errors.map { $0.description(.error) }, [
            "[ERROR] gaps.inner.horizontal: Unsupported type: string, expected: Int or array",
            "[ERROR] gaps.inner.vertical: Unsupported type: bool, expected: Int or array",
            "[ERROR] gaps.outer.left[0].monitor.main: Expected type is 'Int'. But actual type is 'bool'",
            "[ERROR] gaps.outer.right: The last item in the array must be of type Int",
            "[ERROR] gaps.outer.top: The last item in the array must be of type Int",
        ])
        var expectedGaps = Gaps.zero
        expectedGaps.outer.left = .perMonitor([], default: 1)
        assertEquals(result.config.gaps, expectedGaps)
    }

    @Test
    func testResolvedGaps() {
        let result = parseConfig(
            """
            [gaps]
                inner.horizontal = 2
                inner.vertical = [{ monitor.main = 1 }, 5]
                outer.left = [{ monitor."test monitor" = 9 }, 10]
                outer.bottom = [{ monitor."no such monitor" = 11 }, 12]
                outer.top = [{ monitor.secondary = 4 }, 6]
                outer.right = [{ monitor.2 = 3 }, { monitor.1 = 7 }, 8]
            """,
        )
        assertEquals(result.errors, [])
        let gaps = ResolvedGaps(gaps: result.config.gaps, monitor: mainMonitorInfo)
        assertEquals(gaps.inner.horizontal, 2)
        assertEquals(gaps.inner.vertical, 1)
        assertEquals(gaps.outer.left, 9)
        assertEquals(gaps.outer.bottom, 12)
        assertEquals(gaps.outer.top, 6)
        assertEquals(gaps.outer.right, 7)
    }
}
