import Foundation

enum SelectionToolbarConfiguration {
    static let orderDefaultsKey = "selectionToolbar.order-v1"
    static let visibleDefaultsKey = "selectionToolbar.visible-v1"
    static let automaticallySortsByUsageDefaultsKey = "selectionToolbar.autoSortByUsage-v1"
    static let usageCountsDefaultsKey = "selectionToolbar.usageCounts-v1"

    static func manualOrder(defaults: UserDefaults = .standard) -> [SelectionToolbarAction] {
        normalizedOrder(defaults.stringArray(forKey: orderDefaultsKey) ?? [])
    }

    static func setManualOrder(
        _ actions: [SelectionToolbarAction],
        defaults: UserDefaults = .standard
    ) {
        defaults.set(normalizedOrder(actions.map(\.rawValue)).map(\.rawValue), forKey: orderDefaultsKey)
    }

    static func visibleActions(defaults: UserDefaults = .standard) -> Set<SelectionToolbarAction> {
        let stored: Set<SelectionToolbarAction>
        if defaults.object(forKey: visibleDefaultsKey) == nil {
            stored = SelectionToolbarAction.defaultVisibleActions
        } else {
            stored = Set(
                (defaults.stringArray(forKey: visibleDefaultsKey) ?? [])
                    .compactMap(SelectionToolbarAction.init(rawValue:))
                    .filter { SelectionToolbarAction.configurableActions.contains($0) }
            )
        }
        return stored.union(SelectionToolbarAction.requiredActions)
    }

    static func setVisible(
        _ visible: Bool,
        for action: SelectionToolbarAction,
        defaults: UserDefaults = .standard
    ) {
        guard SelectionToolbarAction.configurableActions.contains(action),
              !SelectionToolbarAction.requiredActions.contains(action) else { return }
        var actions = visibleActions(defaults: defaults)
        if visible {
            actions.insert(action)
        } else {
            actions.remove(action)
        }
        defaults.set(
            SelectionToolbarAction.configurableActions
                .filter(actions.contains)
                .map(\.rawValue),
            forKey: visibleDefaultsKey
        )
    }

    static func automaticallySortsByUsage(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: automaticallySortsByUsageDefaultsKey)
    }

    static func setAutomaticallySortsByUsage(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: automaticallySortsByUsageDefaultsKey)
    }

    static func orderedVisibleActions(defaults: UserDefaults = .standard) -> [SelectionToolbarAction] {
        let visible = visibleActions(defaults: defaults)
        let manual = manualOrder(defaults: defaults).filter(visible.contains)
        guard automaticallySortsByUsage(defaults: defaults) else { return manual }

        let counts = usageCounts(defaults: defaults)
        let manualIndex = Dictionary(uniqueKeysWithValues: manual.enumerated().map { ($0.element, $0.offset) })
        return manual.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return manualIndex[lhs, default: 0] < manualIndex[rhs, default: 0]
        }
    }

    static func recordUsage(
        of action: SelectionToolbarAction,
        defaults: UserDefaults = .standard
    ) {
        guard SelectionToolbarAction.configurableActions.contains(action), action != .cancel else { return }
        var counts = usageCounts(defaults: defaults)
        let currentCount = min(counts[action, default: 0], Int.max - 1)
        counts[action] = currentCount + 1
        defaults.set(
            Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }),
            forKey: usageCountsDefaultsKey
        )
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: orderDefaultsKey)
        defaults.removeObject(forKey: visibleDefaultsKey)
        defaults.removeObject(forKey: automaticallySortsByUsageDefaultsKey)
        defaults.removeObject(forKey: usageCountsDefaultsKey)
    }

    private static func normalizedOrder(_ rawValues: [String]) -> [SelectionToolbarAction] {
        var seen = Set<SelectionToolbarAction>()
        var result = rawValues.compactMap(SelectionToolbarAction.init(rawValue:)).filter { action in
            SelectionToolbarAction.configurableActions.contains(action) && seen.insert(action).inserted
        }
        result.append(contentsOf: SelectionToolbarAction.configurableActions.filter { !seen.contains($0) })
        return result
    }

    private static func usageCounts(defaults: UserDefaults) -> [SelectionToolbarAction: Int] {
        let stored = defaults.dictionary(forKey: usageCountsDefaultsKey) ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            guard let action = SelectionToolbarAction(rawValue: entry.key),
                  SelectionToolbarAction.configurableActions.contains(action),
                  let number = entry.value as? NSNumber else { return }
            result[action] = max(number.intValue, 0)
        }
    }
}
