@testable import AppBundle
import Common
import Testing

@Suite
struct ListAppsTest: AeroSpaceTestSuite {
    @Test
    func testParse() {
        assertNotNil(parseCommand("list-apps --macos-native-hidden").cmdOrNil)
        assertNotNil(parseCommand("list-apps --macos-native-hidden no").cmdOrNil)
        assertNotNil(parseCommand("list-apps --format %{app-bundle-id}").cmdOrNil)
        assertNotNil(parseCommand("list-apps --count").cmdOrNil)
        assertEquals(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "Conflicting options: --count, --format")
    }
}
