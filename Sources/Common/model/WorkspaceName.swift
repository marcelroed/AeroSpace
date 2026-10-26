public struct WorkspaceName: Equatable, Sendable {
    public let raw: String

    private init(_ raw: String) {
        self.raw = raw
    }

    public static func parse(_ raw: String) -> ResOrStr<WorkspaceName> {
        if reservedWorkspaceNames.contains(raw) {
            return .failure("'\(raw)' is a reserved workspace name")
        }
        if raw.isEmpty {
            return .failure("Empty workspace name is forbidden")
        }
        if raw.contains(",") {
            return .failure("Workspace names are not allowed to contain comma")
        }
        if raw.starts(with: "_") {
            return .failure("Workspace names starting with underscore are reserved for future use")
        }
        if raw.starts(with: "-") {
            // The syntax conflicts with CLI options. E.g. list-windows --workspace -foo
            return .failure("Workspace names starting with dash are disallowed")
        }
        if raw.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .failure("Whitespace characters are forbidden in workspace names")
        }
        return .success(WorkspaceName(raw))
    }
}

private let reservedWorkspaceNames: Set<String> = [
    "focused", "non-focused", "visible", "invisible", "non-visible", "active", "non-active", "inactive",
    "back-and-forth", "back_and_forth", "previous", "prev", "next",
    "monitor", "workspace", "monitors", "workspaces", "all", "none", "mouse", "target",
]
