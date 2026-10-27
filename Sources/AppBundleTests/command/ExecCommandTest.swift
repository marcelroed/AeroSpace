@testable import AppBundle
import Common
import Testing

@Suite(.aeroSpaceGlobalState)
struct ExecCommandTest {
    /// The bash script is the rest of the line after the command name. The description gives back the configured text
    /// (RB-15: it added a space). GenericParseErrorTest has `exec-and-forgetfoo`
    @Test(arguments: [
        ("exec-and-forget echo 'foo'", " echo 'foo'"),
        ("exec-and-forget\techo foo", "\techo foo"),
        ("exec-and-forget\necho foo\n", "\necho foo\n"),
        ("exec-and-forget", ""),
    ] as [(String, String)])
    func parse(raw: String, bashScript: String) {
        let command = parsedCmd(raw, as: ExecAndForgetCommand.self)
        expectEqual(command?.bashScript, bashScript)
        expectEqual(command?.description, raw)
    }
}
