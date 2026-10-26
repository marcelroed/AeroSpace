import Common

extension BinaryExitCode {
    /// Result of a command that has nothing to do: fail silently with `--fail-if-noop`, otherwise succeed and print `msg`
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

extension EnableCmdArgs.State {
    func resolve(current: Bool) -> Bool {
        switch self {
            case .on: true
            case .off: false
            case .toggle: !current
        }
    }
}
