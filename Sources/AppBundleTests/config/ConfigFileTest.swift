@testable import AppBundle
import Common
import Foundation
import Testing

@Suite
struct ConfigFileTest {
    @Test
    func testConfigPathIsUsedEvenIfTheFileIsMissing() {
        // The --config-path file can be deleted after the startup. Reload must then report it instead of silently
        // falling back to the default config, and "Open config" must not create ~/.aerospace.toml
        let missing = FileManager.default.temporaryDirectory.appending(path: "aerospace-missing-\(UUID().uuidString).toml")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(findCustomConfigUrl(configLocation: missing.path).urlOrNil?.path == missing.path)
    }
}
