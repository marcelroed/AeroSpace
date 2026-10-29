@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct SwiftTestingSupportTest {
    @Test(.aeroSpaceGlobalState) // Applied twice: must not deadlock
    func testTraitIsReentrant() {
        expectEqual(focus.workspace.name, "setUpWorkspacesForTests")
    }
}
