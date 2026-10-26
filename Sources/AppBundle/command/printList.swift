import Common

extension FormattedListCmdArgs {
    /// Prints `list` according to `--format` and `--json`
    @MainActor
    func printList(_ list: [AeroObj], _ io: CmdIo) -> BinaryExitCode {
        if json {
            return switch list.formatToJson(format, ignoreRightPaddingVar: _format.isEmpty) {
                case .success(let json): .succ(io.out(json))
                case .failure(let msg): .fail(io.err(msg))
            }
        } else {
            return switch list.format(format) {
                case .success(let lines): .succ(io.out(lines))
                case .failure(let msg): .fail(io.err(msg.map(\.description).joinErrors()))
            }
        }
    }
}
