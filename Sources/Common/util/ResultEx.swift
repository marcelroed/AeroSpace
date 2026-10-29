extension Result {
    @discardableResult
    public func getOrDie(
        _ msgPrefix: String = "",
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> Success {
        switch self {
            case .success(let suc):
                return suc
            case .failure(let e):
                die(msgPrefix + e.localizedDescription, file: file, line: line, column: column, function: function)
        }
    }
}
