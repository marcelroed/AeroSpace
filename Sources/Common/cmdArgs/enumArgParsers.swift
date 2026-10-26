/// Parses a positional argument into a String-backed enum
func enumPosArg<T: RawRepresentable & CaseIterable & SendableMetatype>(_: T.Type) -> ArgParserFun<PosArgParserInput, T> where T.RawValue == String {
    { i in .init(parseEnum(i.arg, T.self), advanceBy: 1) }
}

/// Parses the value of a flag into a String-backed enum
/// - Parameter placeholder: the name of the value in the error message when the value is missing
func enumSubArg<T: RawRepresentable & CaseIterable & SendableMetatype>(_: T.Type, placeholder: String) -> ArgParserFun<SubArgParserInput, T> where T.RawValue == String {
    { i in
        if let arg = i.nonFlagArgOrNil() {
            .init(parseEnum(arg, T.self), advanceBy: 1)
        } else {
            .fail("\(placeholder) is mandatory", advanceBy: 0)
        }
    }
}
