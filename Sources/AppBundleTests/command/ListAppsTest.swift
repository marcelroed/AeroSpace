@testable import AppBundle
import Common
import Testing

@Suite
struct ListAppsTest {
    @Test
    func testParse() {
        expectEqual(parseCommand("list-apps --macos-native-hidden").failureOrNil, nil)
        expectEqual(parseCommand("list-apps --macos-native-hidden no").failureOrNil, nil)
        expectEqual(parseCommand("list-apps --format %{app-bundle-id}").failureOrNil, nil)
        expectEqual(parseCommand("list-apps --count").failureOrNil, nil)
        expectEqual(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "Conflicting options: --count, --format")
    }
}
