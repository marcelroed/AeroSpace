import Common
import Foundation

let configDotfileName = ".aerospace.toml"
func findCustomConfigUrl(configLocation: String? = serverArgs.configLocation) -> ConfigFile {
    // Use --config-path even if the file was deleted after the startup. Reading it then reports the missing file
    if let configLocation { return .file(URL(filePath: configLocation)) }
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    let candidates: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName),
        xdgConfigHome.appending(path: "aerospace").appending(path: "aerospace.toml"),
    ]
    let existingCandidates = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    return switch existingCandidates.count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates[0])
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
