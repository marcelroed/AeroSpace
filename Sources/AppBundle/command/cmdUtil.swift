import Common

extension BinaryExitCode {
    /// Result of a command that has nothing to do: fail silently with `--fail-if-noop`, otherwise succeed and print `msg`
    @MainActor // BinaryExitCode conforms to a Sendable protocol, so its extensions are nonisolated by default
    static func noop(_ io: CmdIo, failIfNoop: Bool, _ msg: @autoclosure () -> String) -> Self {
        switch failIfNoop {
            case true: .fail
            case false: .succ(io.err(msg()))
        }
    }
}

extension ToggleEnum {
    func resolve(current: Bool) -> Bool {
        switch self {
            case .on: true
            case .off: false
            case .toggle: !current
        }
    }
}

extension DfsNextPrev {
    var indexOffset: Int {
        switch self {
            case .dfsNext: 1
            case .dfsPrev: -1
        }
    }
}
