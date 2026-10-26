public enum Orientation: Sendable {
    /// Windows are placed along the **horizontal** line
    /// x-axis
    case h
    /// Windows are placed along the **vertical** line
    /// y-axis
    case v
}

extension Orientation {
    public var opposite: Orientation { self == .h ? .v : .h }
}
