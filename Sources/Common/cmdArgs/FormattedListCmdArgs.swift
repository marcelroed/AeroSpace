/// Common shape of `list-*` commands that support `--format` and `--json`
public protocol FormattedListCmdArgs: CmdArgs {
    var _format: [InterToken<InterVar>] { get }
    /// The format used when `_format` is empty
    static var defaultFormat: [InterToken<InterVar>] { get }
    var json: Bool { get }
}

extension FormattedListCmdArgs {
    public var format: [InterToken<InterVar>] { _format.isEmpty ? Self.defaultFormat : _format }
}

extension ListAppsCmdArgs: FormattedListCmdArgs {}
extension ListMonitorsCmdArgs: FormattedListCmdArgs {}
extension ListWindowsCmdArgs: FormattedListCmdArgs {}
extension ListWorkspacesCmdArgs: FormattedListCmdArgs {}

extension ParsedCmd where T: FormattedListCmdArgs {
    func filterFormatCompatibleWithJson() -> Self {
        flatMap { if $0.json, let msg = getErrorIfFormatIsIncompatibleWithJson($0._format) { .failure(msg) } else { .cmd($0) } }
    }
}

private func getErrorIfFormatIsIncompatibleWithJson(_ format: [InterToken<InterVar>]) -> String? {
    for x in format {
        switch x {
            case .interVar(.plainInterVar(.rightPadding)):
                return "%{right-padding} interpolation variable is not allowed when --json is used"
            case .interVar: break // skip
            case .literal(let literal):
                if literal.contains(where: { $0 != " " }) {
                    return "Only interpolation variables and spaces are allowed in '--format' when '--json' is used"
                }
        }
    }
    return nil
}
