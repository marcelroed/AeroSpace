import Common

struct Gaps: Equatable, Sendable {
    var inner: Inner
    var outer: Outer

    static let zero = Gaps(inner: .zero, outer: .zero)

    struct Inner: Equatable, Sendable {
        var vertical: DynamicConfigValue<Int>
        var horizontal: DynamicConfigValue<Int>

        static let zero = Inner(vertical: 0, horizontal: 0)
    }

    struct Outer: Equatable, Sendable {
        var left: DynamicConfigValue<Int>
        var bottom: DynamicConfigValue<Int>
        var top: DynamicConfigValue<Int>
        var right: DynamicConfigValue<Int>

        static let zero = Outer(left: 0, bottom: 0, top: 0, right: 0)
    }
}

extension Gaps.Inner {
    init(vertical: Int, horizontal: Int) {
        self.init(vertical: .constant(vertical), horizontal: .constant(horizontal))
    }
}

extension Gaps.Outer {
    init(left: Int, bottom: Int, top: Int, right: Int) {
        self.init(left: .constant(left), bottom: .constant(bottom), top: .constant(top), right: .constant(right))
    }
}

struct ResolvedGaps {
    let inner: Inner
    let outer: Outer

    struct Inner {
        let vertical: Int
        let horizontal: Int

        func get(_ orientation: Orientation) -> Int {
            orientation == .h ? horizontal : vertical
        }
    }

    struct Outer {
        let left: Int
        let bottom: Int
        let top: Int
        let right: Int
    }

    @MainActor init(gaps: Gaps, monitor: MonitorInfo) {
        // Query the monitors at most once, and only if some of the gaps are per-monitor
        lazy var sortedMonitors = sortedMonitorInfos
        inner = .init(
            vertical: gaps.inner.vertical.getValue(for: monitor, sortedMonitors: sortedMonitors),
            horizontal: gaps.inner.horizontal.getValue(for: monitor, sortedMonitors: sortedMonitors),
        )

        outer = .init(
            left: gaps.outer.left.getValue(for: monitor, sortedMonitors: sortedMonitors),
            bottom: gaps.outer.bottom.getValue(for: monitor, sortedMonitors: sortedMonitors),
            top: gaps.outer.top.getValue(for: monitor, sortedMonitors: sortedMonitors),
            right: gaps.outer.right.getValue(for: monitor, sortedMonitors: sortedMonitors),
        )
    }
}

private let gapsParser: [String: Parser<Gaps>] = [
    "inner": Parser(\.inner, parseInner),
    "outer": Parser(\.outer, parseOuter),
]

private let innerParser: [String: Parser<Gaps.Inner>] = [
    "vertical": Parser(\.vertical, parseDynamicValue),
    "horizontal": Parser(\.horizontal, parseDynamicValue),
]

private let outerParser: [String: Parser<Gaps.Outer>] = [
    "left": Parser(\.left, parseDynamicValue),
    "bottom": Parser(\.bottom, parseDynamicValue),
    "top": Parser(\.top, parseDynamicValue),
    "right": Parser(\.right, parseDynamicValue),
]

func parseGaps(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps {
    parseTable(raw, .zero, gapsParser, backtrace, &c)
}

func parseInner(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps.Inner {
    parseTable(raw, Gaps.Inner.zero, innerParser, backtrace, &c)
}

func parseOuter(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Gaps.Outer {
    parseTable(raw, Gaps.Outer.zero, outerParser, backtrace, &c)
}
