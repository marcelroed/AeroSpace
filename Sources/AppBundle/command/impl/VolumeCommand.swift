import AppKit
import Common
import ISSoundAdditions

struct VolumeCommand: nonisolated Command {
    static let resetsClosedWindowsCache = false
    var source: SourceWords = []
    var action: VolumeAction
    var gui = true

    nonisolated enum VolumeAction: Equatable, Sendable {
        case up, down, muteToggle, muteOn, muteOff
        case set(Int)
    }

    static func parse(_ a: inout ArgCursor) throws(CmdParseError) -> Self {
        var gui = true
        while let option = try a.nextOption() {
            switch option {
                case "--no-gui": gui = false
                default: throw .unknownOption(option)
            }
        }
        let action: VolumeAction = switch try a.positional("(up|down|mute-toggle|mute-on|mute-off|set)") {
            case "up": .up
            case "down": .down
            case "mute-toggle": .muteToggle
            case "mute-on": .muteOn
            case "mute-off": .muteOff
            case "set":
                switch Int(try a.positional("<number>")) {
                    case let int? where (0 ... 100).contains(int): .set(int)
                    default: throw "<number> must be an integer from 0 to 100"
                }
            case let arg: throw "Can't parse '\(arg)'.\nPossible values: (up|down|mute-toggle|mute-on|mute-off|set)"
        }
        try a.end()
        return Self(action: action, gui: gui)
    }

    func run(_ cx: CmdContext) throws(CmdFail) {
        switch action {
            case .up:
                Sound.output.increaseVolume(by: 0.0625, autoMuteUnmute: true)
            case .down:
                Sound.output.decreaseVolume(by: 0.0625, autoMuteUnmute: true)
            case .muteToggle:
                Sound.output.isMuted.toggle()
            case .muteOn:
                Sound.output.isMuted = true
            case .muteOff:
                Sound.output.isMuted = false
            case .set(let int):
                Sound.output.setVolume(Float(int) / 100, autoMuteUnmute: true)
        }
        if gui {
            do {
                VolumePanel.shared.update(with: Sound.output.isMuted ? 0 : try Sound.output.readVolume())
            } catch {
                throw CmdFail(bugPrompt(String(describing: error)))
            }
        }
    }
}
