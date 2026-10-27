extension MonitorInfo {
    var visibleRectPaddedByOuterGaps: Rect { visibleRectPadded(by: ResolvedGaps(gaps: config.gaps, monitor: self)) }

    func visibleRectPadded(by gaps: ResolvedGaps) -> Rect {
        let topLeft = visibleRect.topLeftCorner
        return Rect(
            topLeftX: topLeft.x + Double(gaps.outer.left),
            topLeftY: topLeft.y + Double(gaps.outer.top),
            width: visibleRect.width - Double(gaps.outer.left) - Double(gaps.outer.right),
            height: visibleRect.height - Double(gaps.outer.top) - Double(gaps.outer.bottom),
        )
    }

    var monitorId_oneBased: Int? {
        let sorted = sortedMonitorInfos
        let origin = self.rect.topLeftCorner
        return sorted.firstIndex { $0.rect.topLeftCorner == origin }.map { $0 + 1 }
    }
}
