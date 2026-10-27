extension Result {
    public func getOrNil(appendErrorTo errors: inout [Failure]) -> Success? {
        switch self {
            case .success(let success):
                return success
            case .failure(let error):
                errors.append(error)
                return nil
        }
    }

    public func getOrNil(onFailure handle: (Failure) -> ()) -> Success? {
        switch self {
            case .success(let it): return it
            case .failure(let err):
                handle(err)
                return nil
        }
    }

    public func getOrNil(onFailure handle: (Failure) async -> ()) async -> Success? {
        switch self {
            case .success(let it): return it
            case .failure(let err):
                await handle(err)
                return nil
        }
    }
}

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
