import Common
import Foundation

let configDotfileName = ".aerospace.toml"
func findCustomConfigUrl() -> ConfigFile {
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    let candidates: [URL] = switch serverArgs.configLocation {
        case let configLocation?: [URL(filePath: configLocation)]
        case nil:
            [
                FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName),
                xdgConfigHome.appending(path: "aerospace").appending(path: "aerospace.toml"),
            ]
    }
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
