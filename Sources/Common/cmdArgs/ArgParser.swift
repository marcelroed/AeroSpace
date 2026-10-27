public typealias SendableWritableKeyPath<Root, Value> = Sendable & WritableKeyPath<Root, Value>
typealias ArgParserFun<Input, Value> = @Sendable (Input) -> ParsedCliArgs<Value>
typealias SubArgParser<Root> = ArgParser<SubArgParserInput, Root>
typealias PosArgParser<Root> = ArgParser<PosArgParserInput, Root>

/// Parses a flag (and its values) or a positional argument into `Root`
public struct ArgParser<Input, Root>: Sendable {
    /// Positional arguments only: the placeholder reported when the mandatory argument is missing, nil if it's optional
    let argPlaceholderIfMandatory: String?
    /// Parses `input` into `root`, appends the errors to `errors` and returns the number of consumed args
    let parse: @Sendable (_ input: Input, _ root: inout Root, _ errors: inout [String]) -> Int
}

extension ArgParser {
    init<Value>(
        _ keyPath: SendableWritableKeyPath<Root, Value>,
        _ parse: @escaping ArgParserFun<Input, Value>,
        argPlaceholderIfMandatory: String? = nil,
    ) {
        self.init(argPlaceholderIfMandatory: argPlaceholderIfMandatory) { input, root, errors in
            let parsed = parse(input)
            if let value = parsed.value.getOrNil(appendErrorTo: &errors) {
                root[keyPath: keyPath] = value
            }
            return parsed.advanceBy
        }
    }
}

func dashDashArg<Root>(mandatory: Bool) -> PosArgParser<Root> {
    PosArgParser(argPlaceholderIfMandatory: mandatory ? "--" : nil) { input, _, errors in
        switch (input.arg, mandatory) {
            case ("--", _): return 1
            case (_, false): return 0
            case (_, true):
                errors.append("Expected: --. Got: \(input.arg.singleQuoted)")
                return 0
        }
    }
}

func newMandatoryPosArgParser<Root, Value>(
    _ keyPath: SendableWritableKeyPath<Root, Lateinit<Value>>,
    _ parse: @escaping ArgParserFun<PosArgParserInput, Value>,
    placeholder: String,
) -> PosArgParser<Root> {
    ArgParser(keyPath, { parse($0).map { .initialized($0) } }, argPlaceholderIfMandatory: placeholder)
}

// todo reuse in config
public func parseEnum<T: RawRepresentable>(_ raw: String, _ _: T.Type) -> ResOrStr<T> where T.RawValue == String, T: CaseIterable {
    T(rawValue: raw).toResult("Can't parse '\(raw)'.\nPossible values: \(T.unionLiteral)")
}

public func parseUInt32(_ str: String) -> ResOrStr<UInt32> { UInt32(str).toResult("Can't convert '\(str)' to UInt32") }

func upcastArgParserFun<Input, T>(_ fun: @escaping ArgParserFun<Input, T>) -> ArgParserFun<Input, T?> {
    { fun($0).map(Optional.init) }
}
