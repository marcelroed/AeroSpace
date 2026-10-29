extension Workspace {
    func normalizeContainers() {
        existingRootTilingContainer?.unbindEmptyAndAutoFlatten() // Beware! The root may change: flattening replaces it
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            existingRootTilingContainer?.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

extension TilingContainer {
    fileprivate func unbindEmptyAndAutoFlatten() {
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && (child is TilingContainer || !isRootContainer) {
            let mru = parent?.mostRecentChild
            child.move(to: destroy().orDie()) // The child takes the container's place
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            }
            if children.isEmpty && !isRootContainer {
                destroy()
            }
        }
    }
}
