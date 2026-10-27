@testable import AppBundle
import Common
import Testing

@Suite
struct ListAppsTest {
    @Test
    func testParse() {
        #expect(parseCommand("list-apps --macos-native-hidden").cmdOrNil != nil)
        #expect(parseCommand("list-apps --macos-native-hidden no").cmdOrNil != nil)
        #expect(parseCommand("list-apps --format %{app-bundle-id}").cmdOrNil != nil)
        #expect(parseCommand("list-apps --count").cmdOrNil != nil)
        expectEqual(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "Conflicting options: --count, --format")
    }
}
