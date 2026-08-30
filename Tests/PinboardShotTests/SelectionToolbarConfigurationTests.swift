import Foundation
import Testing
@testable import PinboardShot

@Suite("Selection toolbar configuration")
struct SelectionToolbarConfigurationTests {
    @Test("Defaults keep the core completion path visible")
    func defaultConfiguration() throws {
        try withDefaults { defaults in
            #expect(SelectionToolbarConfiguration.manualOrder(defaults: defaults) == SelectionToolbarAction.configurableActions)
            #expect(SelectionToolbarConfiguration.visibleActions(defaults: defaults) == [
                .annotate, .copy, .pin, .cancel
            ])
            #expect(SelectionToolbarConfiguration.orderedVisibleActions(defaults: defaults) == [
                .annotate, .copy, .pin, .cancel
            ])

            SelectionToolbarConfiguration.setVisible(false, for: .copy, defaults: defaults)
            SelectionToolbarConfiguration.setVisible(false, for: .cancel, defaults: defaults)
            #expect(SelectionToolbarConfiguration.visibleActions(defaults: defaults).isSuperset(of: [.copy, .cancel]))
        }
    }

    @Test("Stored order ignores unknown and duplicate values")
    func normalizesStoredOrder() throws {
        try withDefaults { defaults in
            defaults.set(["pin", "unknown", "pin", "pickColor"], forKey: SelectionToolbarConfiguration.orderDefaultsKey)
            #expect(SelectionToolbarConfiguration.manualOrder(defaults: defaults) == [
                .pin, .pickColor, .annotate, .scrollingCapture, .selectionSize, .copy, .cancel
            ])
        }
    }

    @Test("Automatic sorting uses local counts and manual order for ties")
    func automaticSortIsStable() throws {
        try withDefaults { defaults in
            SelectionToolbarConfiguration.setManualOrder(
                [.pin, .copy, .annotate, .scrollingCapture, .pickColor, .selectionSize, .cancel],
                defaults: defaults
            )
            SelectionToolbarConfiguration.recordUsage(of: .pin, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .pin, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .pin, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .copy, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .copy, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .annotate, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .annotate, defaults: defaults)
            SelectionToolbarConfiguration.recordUsage(of: .cancel, defaults: defaults)
            SelectionToolbarConfiguration.setAutomaticallySortsByUsage(true, defaults: defaults)

            #expect(SelectionToolbarConfiguration.orderedVisibleActions(defaults: defaults) == [
                .pin, .copy, .annotate, .cancel
            ])
        }
    }

    @Test("Visibility and reset remain reversible")
    func visibilityAndReset() throws {
        try withDefaults { defaults in
            SelectionToolbarConfiguration.setVisible(true, for: .pickColor, defaults: defaults)
            SelectionToolbarConfiguration.setVisible(false, for: .pin, defaults: defaults)
            SelectionToolbarConfiguration.setAutomaticallySortsByUsage(true, defaults: defaults)
            #expect(SelectionToolbarConfiguration.visibleActions(defaults: defaults).contains(.pickColor))
            #expect(!SelectionToolbarConfiguration.visibleActions(defaults: defaults).contains(.pin))

            SelectionToolbarConfiguration.reset(defaults: defaults)
            #expect(SelectionToolbarConfiguration.visibleActions(defaults: defaults) == SelectionToolbarAction.defaultVisibleActions)
            #expect(!SelectionToolbarConfiguration.automaticallySortsByUsage(defaults: defaults))
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "SelectionToolbarConfigurationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
