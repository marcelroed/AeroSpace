import Common

/// The stdin of a request. Not copyable, so only one command reads it
struct CmdStdin: ~Copyable {
    private var input: String = ""
    init(_ input: String) {
        self.input = input
    }
    static var emptyStdin: CmdStdin { .init("") }

    mutating func readAll() -> String {
        let result = input
        input = ""
        return result
    }
}

/// What a command reads and writes. The server sends `stdout` and `stderr` back to the CLI. A class: the commands of one
/// shell line share it
final class CmdIo {
    private var stdin: CmdStdin
    /// The left side of a pipe reads the stdin of the line on demand: what it doesn't read stays for the next command
    private let stdinSource: CmdIo?
    var stdout: [String] = []
    var stderr: [String] = []

    init(stdin: consuming CmdStdin) {
        self.stdin = stdin
        stdinSource = nil
    }

    init(forwardingStdinOf stdinSource: CmdIo) {
        stdin = .emptyStdin
        self.stdinSource = stdinSource
    }

    func readStdin() -> String { stdinSource?.readStdin() ?? stdin.readAll() }

    static var emptyStdinIgnoringOut: CmdIo { CmdIo(stdin: .emptyStdin) }
}

/// What a shell line answers: its output and its exit code
struct CmdResult: Equatable {
    let stdout: [String]
    let stderr: [String]
    let exitCode: Int32
}
