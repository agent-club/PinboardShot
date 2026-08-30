import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PreferencesWindowMetrics {
    static let width: CGFloat = 840
    static let height: CGFloat = 580

    static func centeredOrigin(windowSize: CGSize, in screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )
    }
}

enum PreferencesSection: String, CaseIterable, Identifiable {
    case shortcuts
    case history
    case pins
    case ocr
    case watermark
    case toolbar
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: L10n.text("preferences.shortcuts")
        case .history: L10n.text("preferences.history")
        case .pins: L10n.text("pinWorkspace.preferencesTab")
        case .ocr: L10n.text("ocr.preferences.tab")
        case .watermark: L10n.text("watermark.preferences.tab")
        case .toolbar: L10n.text("preferences.toolbar")
        case .general: L10n.text("preferences.general")
        }
    }

    var systemImage: String {
        switch self {
        case .shortcuts: "keyboard"
        case .history: "clock"
        case .pins: "rectangle.stack"
        case .ocr: "text.viewfinder"
        case .watermark: "eye.slash"
        case .toolbar: "slider.horizontal.2.square"
        case .general: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .shortcuts: .accentColor
        case .history: .orange
        case .pins: .pink
        case .ocr: .purple
        case .watermark: .blue
        case .toolbar: .indigo
        case .general: .teal
        }
    }
}

@MainActor
final class PreferencesNavigationModel: ObservableObject {
    @Published var selectedSection: PreferencesSection = .shortcuts
}

@MainActor
final class AppHealthModel: ObservableObject {
    @Published var screenCapturePermissionGranted = false
    @Published var failedHotKeyCount = 0

    var isReady: Bool { screenCapturePermissionGranted && failedHotKeyCount == 0 }
}

struct PreferencesView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject var historyStore: HistoryStore
    @ObservedObject var pinWorkspaceStore: PinWorkspaceStore
    @ObservedObject var watermarkStore: InvisibleWatermarkStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var localizationStore: LocalizationStore
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var navigation: PreferencesNavigationModel
    @ObservedObject var appHealth: AppHealthModel
    let onShortcutsChanged: () -> Void
    let onPinShadowChanged: (Bool) -> Void
    let onTrayIconChanged: (TrayIconChoice) -> Void
    let onPinHistoryItem: (HistoryItem) -> Void
    let onCopyHistoryItem: (HistoryItem) -> Void
    let onSaveHistoryItem: (HistoryItem) -> Void
    let onCreateBoard: () -> Void
    let onSavePinWorkspace: (String) throws -> PinWorkspaceSummary
    let onRestorePinWorkspace: (PinWorkspaceSummary) throws -> PinWorkspaceRestoreReport
    let onRenamePinWorkspace: (PinWorkspaceSummary, String) throws -> PinWorkspaceSummary
    let onDuplicatePinWorkspace: (PinWorkspaceSummary, String?) throws -> PinWorkspaceSummary
    let onExportPinWorkspace: (PinWorkspaceSummary, PinWorkspaceExportFormat) throws -> PinWorkspaceExportReport?
    let onDeletePinWorkspace: (PinWorkspaceSummary) throws -> Void
    let onPinSessionRecoveryChanged: (Bool) -> Void
    let onReindexHistoryItem: (HistoryItem) -> Void
    let onRequestScreenCapturePermission: () -> Void
    let onOpenScreenCaptureSettings: () -> Void

    @AppStorage("captureCursor") private var captureCursor = false
    @AppStorage(CaptureQuality.userDefaultsKey)
    private var captureQualityRawValue = CaptureQuality.defaultValue.rawValue
    @AppStorage("clearHistoryOnQuit") private var clearHistoryOnQuit = false
    @AppStorage(OverlaySafetyPolicy.animationDefaultsKey) private var captureEntranceAnimation = true
    @AppStorage(CaptureImageValidator.allowUniformDarkDefaultsKey) private var allowUniformDarkCaptures = false
    @AppStorage(PinWindowManager.shadowDefaultsKey) private var pinWindowShadow = true
    @AppStorage(QuickCaptureOverlaySettings.enabledDefaultsKey) private var quickCaptureOverlayEnabled = true
    @AppStorage(TrayIconChoice.userDefaultsKey)
    private var trayIconRawValue = TrayIconChoice.defaultChoice.rawValue
    @AppStorage(InvisibleWatermarkSettings.enabledDefaultsKey)
    private var invisibleWatermarkEnabled = false
    @AppStorage(InvisibleWatermarkSettings.customTextDefaultsKey)
    private var watermarkCustomText = ""
    @AppStorage(InvisibleWatermarkSettings.projectDefaultsKey)
    private var watermarkProject = ""
    @AppStorage(InvisibleWatermarkSettings.recipientDefaultsKey)
    private var watermarkRecipient = ""
    @AppStorage(HistorySettings.enabledDefaultsKey) private var historyEnabled = true
    @AppStorage(HistorySettings.maximumItemsDefaultsKey) private var historyMaximumItems = 50
    @AppStorage(HistorySettings.retentionDaysDefaultsKey) private var historyRetentionDays = 0
    @AppStorage(HistorySettings.ocrIndexingDefaultsKey) private var historyOCRIndexingEnabled = true
    @AppStorage(PinSessionRecoverySettings.defaultsKey) private var pinSessionRecoveryEnabled = false
    private let historyPrivacySettings = HistoryPrivacySettings()
    @State private var shortcutMessage: String?
    @State private var isAddingShortcut = false
    @State private var isConfirmingClearOCRIndex = false
    @State private var historyClearPreview: HistoryCleanupPreview?
    @State private var historyClearLabel = ""
    @State private var selectedHistoryItemForDetail: HistoryItem?
    @State private var isPreparingHistoryCleanup = false
    @State private var historyCleanupDays = 7
    @State private var isClearingHistoryItems = false
    @State private var isAddingHistoryExclusion = false
    @State private var excludedApplications: [HistoryExcludedApplication] = []
    @State private var isHistoryStorageExpanded = true
    @State private var isHistoryExclusionsExpanded = true
    @State private var excludedApplicationMessage: String?
    @State private var historyStorageMetrics: HistoryStorageMetrics?
    @State private var pinWorkspaceStorageMetrics: PinWorkspaceStorageMetrics?
    @State private var storageMetricsError: String?
    @State private var historyErrorMessage: String?
    @State private var isConfirmingWatermarkClear = false
    @State private var watermarkErrorMessage: String?
    @State private var historySearch = ""
    @State private var ocrPlugins = [OCRPluginManifest.openAICompatible]
    @State private var ocrPluginLoadErrors: [String] = []
    @State private var ocrProviderID = OCRPluginSettings.selectedProviderID()
    @State private var ocrBaseURL = ""
    @State private var ocrModel = ""
    @State private var ocrAPIKey = ""
    @State private var ocrHasSavedAPIKey = false
    @State private var ocrStatusMessage: String?
    @State private var ocrStatusIsError = false
    @State private var pinWorkspaceName = ""
    @State private var pinWorkspaceSearch = ""
    @State private var pinWorkspaceSort = PinWorkspaceSort.updatedNewest
    @State private var pinWorkspaceStatusMessage: String?
    @State private var pinWorkspaceStatusIsError = false
    @State private var pinWorkspacePendingDeletion: PinWorkspaceSummary?
    @State private var pinWorkspacePendingRename: PinWorkspaceSummary?
    @State private var pinWorkspaceRenameText = ""
    @State private var pinWorkspacePendingDuplicate: PinWorkspaceSummary?
    @State private var pinWorkspaceDuplicateText = ""
    @State private var toolbarActionOrder: [SelectionToolbarAction] = SelectionToolbarConfiguration.manualOrder(defaults: UserDefaults.standard)
    @State private var toolbarVisibleActions: [String: Bool] = Dictionary(
        uniqueKeysWithValues: SelectionToolbarConfiguration.visibleActions(defaults: UserDefaults.standard)
            .map { action in
                (action.rawValue, true)
            }
    )
    @State private var toolbarAutoSort: Bool = SelectionToolbarConfiguration.automaticallySortsByUsage(defaults: UserDefaults.standard)
    @Namespace private var sidebarSelection

    private var selectedSection: PreferencesSection { navigation.selectedSection }

    var body: some View {
        HStack(spacing: 0) {
            preferencesSidebar
            Divider()
            preferencesContent
        }
        .frame(width: PreferencesWindowMetrics.width, height: PreferencesWindowMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var preferencesSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "viewfinder.rectangular")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))

                Text("PinboardShot")
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(PreferencesSection.allCases) { section in
                    PreferencesSidebarButton(
                        section: section,
                        isSelected: selectedSection == section,
                        selectionNamespace: sidebarSelection,
                        action: { select(section) }
                    )
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(appHealth.isReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(L10n.text(appHealth.isReady ? "menu.ready" : "preferences.healthNeedsAttention"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(16)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private var preferencesContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: selectedSection.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selectedSection.tint)
                    .frame(width: 30, height: 30)
                    .background(selectedSection.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

                Text(selectedSection.title)
                    .font(.title2.bold())

                Spacer()
                pageHeaderAction
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)

            Divider()

            ZStack(alignment: .topLeading) {
                selectedContent
                    .id(selectedSection)
                    .transition(contentTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }

    @ViewBuilder
    private var pageHeaderAction: some View {
        switch selectedSection {
        case .shortcuts:
            Button {
                isAddingShortcut = true
            } label: {
                Label(L10n.text("preferences.addShortcut"), systemImage: "plus")
            }
        case .history:
            Button {
                onCreateBoard()
            } label: {
                Label(L10n.text("composition.create"), systemImage: "rectangle.3.group")
            }
            .disabled(historyStore.items.isEmpty)
        case .pins, .ocr, .watermark, .toolbar, .general:
            EmptyView()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .shortcuts: shortcutsTab
        case .history: historyTab
        case .pins: pinWorkspacesTab
        case .ocr: ocrTab
        case .watermark: watermarkTab
        case .toolbar: toolbarTab
        case .general: privacyTab
        }
    }

    private var contentTransition: AnyTransition {
        guard !accessibilityReduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 10).combined(with: .opacity),
            removal: .offset(x: -6).combined(with: .opacity)
        )
    }

    private func select(_ section: PreferencesSection) {
        guard section != selectedSection else { return }
        if accessibilityReduceMotion {
            navigation.selectedSection = section
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                navigation.selectedSection = section
            }
        }
    }

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("preferences.shortcutHelp"))
                .foregroundStyle(.secondary)

            List {
                ForEach(shortcutStore.bindings) { binding in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.action.title)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ShortcutRecorderButton(shortcut: binding.shortcut) { shortcut in
                            if shortcutStore.update(bindingID: binding.id, shortcut: shortcut) {
                                shortcutMessage = nil
                                onShortcutsChanged()
                            } else {
                                shortcutMessage = L10n.text("preferences.shortcutConflict")
                            }
                        }
                        .frame(width: 130, height: 28)

                        Button(role: .destructive) {
                            shortcutStore.remove(bindingID: binding.id)
                            shortcutMessage = nil
                            onShortcutsChanged()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("preferences.deleteShortcut"))
                    }
                }
            }
            .listStyle(.inset)

            if let shortcutMessage {
                Text(shortcutMessage).foregroundStyle(.red).font(.callout)
            }

            Spacer()
            HStack {
                Button(L10n.text("preferences.restoreShortcuts")) {
                    shortcutStore.reset()
                    onShortcutsChanged()
                }
                .disabled(shortcutStore.bindings.isEmpty)
                Spacer()
            }
        }
        .padding(12)
        .sheet(isPresented: $isAddingShortcut) {
            AddShortcutSheet { action, shortcut in
                guard shortcutStore.add(action: action, shortcut: shortcut) != nil else {
                    shortcutMessage = L10n.text("preferences.shortcutConflict")
                    return false
                }
                shortcutMessage = nil
                onShortcutsChanged()
                return true
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(L10n.text("preferences.historyEnabled"), isOn: $historyEnabled)
                Spacer()
            }
            Toggle(L10n.text("preferences.pinSessionRecovery.title"), isOn: $pinSessionRecoveryEnabled)
                .onChange(of: pinSessionRecoveryEnabled) { _, enabled in
                    onPinSessionRecoveryChanged(enabled)
                }
                .help(L10n.text("preferences.pinSessionRecovery.help"))
            Toggle(L10n.text("preferences.historyOCRIndexing"), isOn: $historyOCRIndexingEnabled)

            if let historyErrorMessage {
                Text(historyErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Picker(L10n.text("preferences.historyMaximumItems"), selection: $historyMaximumItems) {
                    ForEach([10, 25, 50, 100, 250], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .frame(width: 120)
                Spacer()
                Picker(L10n.text("preferences.historyRetention"), selection: $historyRetentionDays) {
                    Text(L10n.text("preferences.historyRetention.forever")).tag(0)
                    Text(L10n.text("preferences.historyRetention.oneDay")).tag(1)
                    Text(L10n.text("preferences.historyRetention.sevenDays")).tag(7)
                    Text(L10n.text("preferences.historyRetention.thirtyDays")).tag(30)
                    Text(L10n.text("preferences.historyRetention.ninetyDays")).tag(90)
                }
                .frame(width: 160)
            }

            TextField(L10n.text("preferences.historySearch"), text: $historySearch)
                .textFieldStyle(.roundedBorder)
                .help(L10n.text("history.searchHelp"))

            HStack {
                Picker(L10n.text("history.clearByTime"), selection: $historyCleanupDays) {
                    Text(L10n.text("history.cleanupOneDay")).tag(1)
                    Text(L10n.text("history.cleanupSevenDays")).tag(7)
                    Text(L10n.text("history.cleanupThirtyDays")).tag(30)
                    Text(L10n.text("history.cleanupNinetyDays")).tag(90)
                    Text(L10n.text("history.cleanupAll")).tag(0)
                }
                .pickerStyle(.segmented)
                .help(L10n.text("history.cleanupHelp"))
                Spacer()
                Button(L10n.text("history.clearByTime")) {
                    prepareHistoryCleanup()
                }
                .disabled(historyStore.items.isEmpty)
            }

            DisclosureGroup(L10n.text("history.storageAndPrivacy"), isExpanded: $isHistoryStorageExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(L10n.text("history.refreshStorage")) {
                            loadHistoryStorageMetrics()
                        }
                        Spacer()
                        Button(L10n.text("history.clearOCRIndex"), role: .destructive) {
                            isConfirmingClearOCRIndex = true
                        }
                        .help(L10n.text("history.clearOCRIndexHelp"))
                    }

                    if let historyStorageMetrics {
                        Text(L10n.text("history.storageHistory", historyStorageMetrics.itemCount))
                        Text(L10n.text("history.storageHistoryImages", formatBytes(historyStorageMetrics.imageBytes)))
                        Text(L10n.text("history.storageHistoryIndex", formatBytes(historyStorageMetrics.indexBytes)))
                    }
                    if let pinWorkspaceStorageMetrics {
                        Text(L10n.text("pinWorkspace.storageSummary", pinWorkspaceStorageMetrics.totalBytes))
                        Text(L10n.text("pinWorkspace.storageWorkspaceCount", pinWorkspaceStorageMetrics.workspaceCount))
                        Text(L10n.text("pinWorkspace.storageRecovery", pinWorkspaceStorageMetrics.recoveryBytes))
                        Text(L10n.text("pinWorkspace.storagePins", pinWorkspaceStorageMetrics.pinCount))
                    }
                    if let storageMetricsError {
                        Text(storageMetricsError).foregroundStyle(.red).font(.caption)
                    }

                    Divider()
                    DisclosureGroup(L10n.text("history.applicationExclusions"), isExpanded: $isHistoryExclusionsExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let message = excludedApplicationMessage {
                                Text(message).foregroundStyle(.red).font(.caption)
                            }
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(excludedApplications) { application in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(historyApplicationName(for: application.bundleIdentifier))
                                                    .lineLimit(1)
                                                Text(application.bundleIdentifier)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button(role: .destructive) {
                                                historyPrivacySettings.remove(bundleIdentifier: application.bundleIdentifier)
                                                loadHistoryPrivacyApplications()
                                            } label: {
                                                Image(systemName: "xmark.circle")
                                            }
                                            .buttonStyle(.borderless)
                                            .help(L10n.text("history.removeExcludedApplication"))
                                            .accessibilityLabel(L10n.text("history.removeExcludedApplication"))
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 120)
                            if excludedApplications.isEmpty {
                                Text(L10n.text("history.noExcludedApplications"))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Button(L10n.text("history.addExcludedApplication"), action: addHistoryExcludedApplication)
                        }
                    }
                    Text(L10n.text("history.exclusionFailClosedHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            List(filteredHistoryItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        HistoryThumbnailView(historyStore: historyStore, item: item)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.createdAt, style: .date)
                                .lineLimit(1)
                            Text(item.createdAt, style: .time)
                                .foregroundStyle(.secondary)
                            Text("\(item.pixelWidth) × \(item.pixelHeight)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            onCopyHistoryItem(item)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("pin.copy"))
                        .accessibilityLabel(L10n.text("pin.copy"))
                        Button(role: .none) {
                            onPinHistoryItem(item)
                        } label: {
                            Image(systemName: "pin")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("preferences.pinToScreen"))
                        .accessibilityLabel(L10n.text("preferences.pinToScreen"))
                        Button {
                            onSaveHistoryItem(item)
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("pin.save"))
                        .accessibilityLabel(L10n.text("pin.save"))
                        Button(role: .destructive) {
                            deleteHistoryItem(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("preferences.deleteHistoryItem"))
                        .accessibilityLabel(L10n.text("preferences.deleteHistoryItem"))
                    }
                    HStack(spacing: 8) {
                        Text(historyOCRStatusText(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if item.ocrStatus == .indexed {
                            Button {
                                copyHistoryOCRText(item)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.text("history.copyRecognizedText"))
                            .accessibilityLabel(L10n.text("history.copyRecognizedText"))
                        }
                        Button {
                            selectedHistoryItemForDetail = item
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text("history.viewDetails"))
                        .accessibilityLabel(L10n.text("history.viewDetails"))
                        if item.ocrStatus == .notIndexed || item.ocrStatus == .empty || item.ocrStatus == .failed {
                            Button {
                                onReindexHistoryItem(item)
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.text("history.reindex"))
                            .accessibilityLabel(L10n.text("history.reindex"))
                        }
                    }
                    Text(HistorySearchMatcher.summary(for: item, maximumLength: 140))
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
        .padding(12)
        .onAppear {
            loadHistoryPrivacyApplications()
            loadHistoryStorageMetrics()
            historyClearLabel = ""
        }
        .onChange(of: historyMaximumItems) { _, _ in applyHistoryRetentionPolicy() }
        .onChange(of: historyRetentionDays) { _, _ in applyHistoryRetentionPolicy() }
        .confirmationDialog(
            L10n.text("history.clearByTime"),
            isPresented: $isPreparingHistoryCleanup,
            titleVisibility: .visible
        ) {
            Button(L10n.text("history.clearHistory"), role: .destructive) {
                clearHistoryItemsUsingPreview()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                historyClearPreview = nil
            }
        } message: {
            if let preview = historyClearPreview {
                Text(L10n.text("history.clearHistoryMessage", preview.itemCount, formatBytes(preview.reclaimableBytes)))
            }
        }
        .confirmationDialog(
            L10n.text("history.clearOCRIndex"),
            isPresented: $isConfirmingClearOCRIndex,
            titleVisibility: .visible
        ) {
            Button(L10n.text("history.clearOCRIndex"), role: .destructive) {
                clearHistoryOCRIndex()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("history.clearOCRIndexMessage"))
        }
        .sheet(isPresented: Binding(
            get: { selectedHistoryItemForDetail != nil },
            set: { if !$0 { selectedHistoryItemForDetail = nil } }
        )) {
            if let selectedItem = selectedHistoryItemForDetail {
                historyItemDetailSheet(for: selectedItem)
            }
        }
        .alert(isPresented: $isClearingHistoryItems) {
            Alert(
                title: Text(L10n.text("history.clearHistoryTitle")),
                message: Text(historyClearLabel),
                primaryButton: .default(Text(L10n.text("common.ok")),
                                       action: {
                    isClearingHistoryItems = false
                }),
                secondaryButton: .cancel()
            )
        }
    }

    private var pinWorkspacesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Section(L10n.text("pinWorkspace.saveSection")) {
                    HStack {
                        TextField(L10n.text("pinWorkspace.namePlaceholder"), text: $pinWorkspaceName)
                            .onSubmit(savePinWorkspace)
                        Button(L10n.text("pinWorkspace.save"), action: savePinWorkspace)
                            .disabled(pinWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(L10n.text("pinWorkspace.saveHelp"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.text("pinWorkspace.savedSection")) {
                    HStack(spacing: 8) {
                        TextField(L10n.text("preferences.search"), text: $pinWorkspaceSearch)
                            .textFieldStyle(.roundedBorder)
                            .help(L10n.text("history.searchHelp"))
                        Picker(L10n.text("pinWorkspace.sort"), selection: $pinWorkspaceSort) {
                            Text(L10n.text("pinWorkspace.sortUpdated")).tag(PinWorkspaceSort.updatedNewest)
                            Text(L10n.text("pinWorkspace.sortName")).tag(PinWorkspaceSort.nameAscending)
                            Text(L10n.text("pinWorkspace.sortRestored")).tag(PinWorkspaceSort.recentlyRestored)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 168)
                    }

                    if pinWorkspaceStore.workspaces.isEmpty {
                        ContentUnavailableView(
                            L10n.text("pinWorkspace.emptyTitle"),
                            systemImage: "rectangle.stack",
                            description: Text(L10n.text("pinWorkspace.emptyMessage"))
                        )
                    } else if filteredPinWorkspaceStoreItems.isEmpty {
                        ContentUnavailableView.search(text: pinWorkspaceSearch)
                    } else {
                        ForEach(filteredPinWorkspaceStoreItems) { workspace in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.stack.fill")
                                        .foregroundStyle(.pink)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workspace.name)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        Text(L10n.text(
                                            "pinWorkspace.recentSummary",
                                            workspace.lastRestoredAt.map { formattedHistoryDate($0) } ?? L10n.text("pinWorkspace.notRestored"),
                                            workspace.noteCount,
                                            workspace.aggregateTags.prefix(3).joined(separator: ", ")
                                        ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button(L10n.text("pinWorkspace.restore")) {
                                        restorePinWorkspace(workspace)
                                    }
                                    .help(L10n.text("pinWorkspace.restore"))
                                    Menu {
                                        Button(L10n.text("pinWorkspace.rename")) {
                                            pinWorkspacePendingRename = workspace
                                            pinWorkspaceRenameText = workspace.name
                                        }
                                        Button(L10n.text("pinWorkspace.duplicate")) {
                                            pinWorkspacePendingDuplicate = workspace
                                            pinWorkspaceDuplicateText = ""
                                        }
                                        Divider()
                                        Button(L10n.text("pinWorkspace.exportImages")) {
                                            exportPinWorkspace(workspace, format: .images)
                                        }
                                        Button(L10n.text("pinWorkspace.exportPDF")) {
                                            exportPinWorkspace(workspace, format: .pdf)
                                        }
                                        Button(L10n.text("pinWorkspace.exportMarkdown")) {
                                            exportPinWorkspace(workspace, format: .markdown)
                                        }
                                        Divider()
                                        Button(L10n.text("pinWorkspace.delete"), role: .destructive) {
                                            pinWorkspacePendingDeletion = workspace
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .help(L10n.text("pinWorkspace.moreActions"))
                                    .accessibilityLabel(L10n.text("pinWorkspace.moreActions"))
                                }
                                Text(L10n.text("pinWorkspace.itemSummary", workspace.pinCount, workspace.updatedAt.formatted()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(L10n.text("pinWorkspace.restoreAgain")) {
                                    restorePinWorkspace(workspace)
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }

                    if pinWorkspaceStore.loadWarningCount > 0 {
                        Label(
                            L10n.text("pinWorkspace.loadWarnings", pinWorkspaceStore.loadWarningCount),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text(L10n.text("pinWorkspace.privacyHelp"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let pinWorkspaceStatusMessage {
                    Section {
                        Text(pinWorkspaceStatusMessage)
                            .foregroundStyle(pinWorkspaceStatusIsError ? .red : .secondary)
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            pinWorkspaceStore.refresh()
            loadPinWorkspaceStorageMetrics()
        }
        .alert(
            L10n.text("pinWorkspace.deleteTitle"),
            isPresented: Binding(
                get: { pinWorkspacePendingDeletion != nil },
                set: { if !$0 { pinWorkspacePendingDeletion = nil } }
            ),
            presenting: pinWorkspacePendingDeletion
        ) { workspace in
            Button(L10n.text("pinWorkspace.delete"), role: .destructive) {
                deletePinWorkspace(workspace)
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: { workspace in
            Text(L10n.text("pinWorkspace.deleteMessage", workspace.name))
        }
        .sheet(item: $pinWorkspacePendingRename) { workspace in
            pinWorkspaceRenameSheet(for: workspace)
        }
        .sheet(item: $pinWorkspacePendingDuplicate) { workspace in
            pinWorkspaceDuplicateSheet(for: workspace)
        }
    }

    private func savePinWorkspace() {
        do {
            let workspace = try onSavePinWorkspace(pinWorkspaceName)
            pinWorkspaceName = ""
            pinWorkspaceStatusMessage = L10n.text(
                "pinWorkspace.savedMessage",
                workspace.name,
                workspace.pinCount
            )
            pinWorkspaceStatusIsError = false
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
    }

    private func deletePinWorkspace(_ workspace: PinWorkspaceSummary) {
        do {
            try onDeletePinWorkspace(workspace)
            pinWorkspaceStatusMessage = L10n.text("pinWorkspace.deletedMessage", workspace.name)
            pinWorkspaceStatusIsError = false
            pinWorkspaceStore.refresh()
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
        pinWorkspacePendingDeletion = nil
    }

    private var filteredHistoryItems: [HistoryItem] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return historyStore.items }
        return historyStore.items.filter { item in
            HistorySearchMatcher.matches(
                item,
                query: query,
                displayName: historyApplicationName(for: item.sourceApplicationBundleIdentifier)
            )
        }
    }

    private var filteredPinWorkspaceStoreItems: [PinWorkspaceSummary] {
        pinWorkspaceStore.matchingWorkspaces(
            query: pinWorkspaceSearch,
            sort: pinWorkspaceSort
        )
    }

    private func historyApplicationName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        guard let appBundle = Bundle(url: url) else {
            return url.deletingPathExtension().lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !value.isEmpty {
            return value
        }
        if let value = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !value.isEmpty {
            return value
        }
        return url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatBytes(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }

    private func formattedHistoryDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func historyOCRStatusText(for item: HistoryItem) -> String {
        switch item.ocrStatus {
        case .notIndexed:
            return L10n.text("history.status.notIndexed")
        case .pending:
            return L10n.text("history.status.pending")
        case .indexed:
            return L10n.text("history.status.indexed")
        case .empty:
            return L10n.text("history.status.empty")
        case .failed:
            return L10n.text("history.status.failed")
        }
    }

    private func copyHistoryOCRText(_ item: HistoryItem) {
        guard item.ocrStatus == .indexed, let text = item.recognizedText else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func historyItemDetailSheet(for item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.createdAt.formatted())
                    .font(.headline)
                Spacer()
                Button(L10n.text("common.close")) {
                    selectedHistoryItemForDetail = nil
                }
            }
            Text(L10n.text("history.dimension", item.pixelWidth, item.pixelHeight))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let image = historyStore.image(for: item) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 220)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(L10n.text("history.imageMissing"))
                    .foregroundStyle(.red)
            }
            if let text = item.recognizedText, !text.isEmpty {
                Text(L10n.text("history.ocrTextTitle"))
                    .font(.callout)
                    .bold()
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            } else {
                Text(L10n.text("history.noRecognizedText"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(width: 560, height: 480)
    }

    private func loadHistoryStorageMetrics() {
        do {
            storageMetricsError = nil
            historyStorageMetrics = try historyStore.storageMetrics()
        } catch {
            storageMetricsError = error.localizedDescription
        }
        loadPinWorkspaceStorageMetrics()
    }

    private func loadPinWorkspaceStorageMetrics() {
        do {
            storageMetricsError = nil
            pinWorkspaceStorageMetrics = try pinWorkspaceStore.storageMetrics()
        } catch {
            storageMetricsError = error.localizedDescription
        }
    }

    private func loadHistoryPrivacyApplications() {
        excludedApplicationMessage = nil
        excludedApplications = historyPrivacySettings.excludedApplications
    }

    private func addHistoryExcludedApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = L10n.text("common.add")
        panel.message = L10n.text("history.chooseApplication")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK else { return }
            guard let url = panel.url else { return }
            guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
                excludedApplicationMessage = L10n.text("history.exclusionNoBundle")
                return
            }
            guard let currentBundleIdentifier = Bundle.main.bundleIdentifier else {
                excludedApplicationMessage = L10n.text("history.exclusionUnknownSelf")
                return
            }
            if bundleIdentifier.lowercased() == currentBundleIdentifier.lowercased() {
                excludedApplicationMessage = L10n.text("history.exclusionSelf")
                return
            }
            historyPrivacySettings.add(bundleIdentifier: bundleIdentifier)
            loadHistoryPrivacyApplications()
        }
    }

    private func prepareHistoryCleanup() {
        isPreparingHistoryCleanup = false
        isClearingHistoryItems = false
        historyClearLabel = ""
        let cutoff = historyCleanupDays == 0
            ? Date.distantFuture
            : Date().addingTimeInterval(-Double(historyCleanupDays * 24 * 60 * 60))
        do {
            let preview = try historyStore.cleanupPreview(olderThan: cutoff)
            historyClearPreview = preview
            if preview.itemCount == 0 {
                historyClearLabel = L10n.text("history.clearHistoryNone", preview.itemCount)
                isClearingHistoryItems = true
            } else {
                isPreparingHistoryCleanup = true
            }
        } catch {
            historyClearLabel = error.localizedDescription
            isClearingHistoryItems = true
        }
    }

    private func clearHistoryItemsUsingPreview() {
        isPreparingHistoryCleanup = false
        guard let preview = historyClearPreview else {
            isClearingHistoryItems = true
            historyClearLabel = L10n.text("history.clearHistoryFailed", "")
            return
        }
        do {
            let removed = try historyStore.clearItems(matching: preview)
            historyClearLabel = L10n.text("history.clearHistoryDone", removed)
            historyClearPreview = nil
            loadHistoryStorageMetrics()
            isClearingHistoryItems = true
        } catch {
            historyClearLabel = L10n.text("history.clearHistoryFailed", error.localizedDescription)
            isClearingHistoryItems = true
        }
    }

    private func clearHistoryOCRIndex() {
        do {
            try historyStore.clearOCRIndex()
            historyErrorMessage = nil
            isConfirmingClearOCRIndex = false
        } catch {
            historyErrorMessage = error.localizedDescription
        }
        isConfirmingClearOCRIndex = false
    }

    private func deleteHistoryItem(_ item: HistoryItem) {
        do {
            try historyStore.delete(item)
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = L10n.text("preferences.deleteHistoryItemFailed", error.localizedDescription)
        }
    }

    private func applyHistoryRetentionPolicy() {
        do {
            try historyStore.applyRetentionPolicy()
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = L10n.text("preferences.historyPolicyFailed", error.localizedDescription)
        }
    }

    private func restorePinWorkspace(_ workspace: PinWorkspaceSummary) {
        do {
            let report = try onRestorePinWorkspace(workspace)
            if report.skippedPinCount > 0 || report.clearedApplicationBindingCount > 0 {
                pinWorkspaceStatusMessage = L10n.text(
                    "pinWorkspace.restoredWithWarnings",
                    report.restoredPinCount,
                    report.skippedPinCount,
                    report.clearedApplicationBindingCount
                )
            } else {
                pinWorkspaceStatusMessage = L10n.text(
                    "pinWorkspace.restoredMessage",
                    workspace.name,
                    report.restoredPinCount
                )
            }
            pinWorkspaceStatusIsError = false
            pinWorkspaceStore.refresh()
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
    }

    private func renamePinWorkspace(_ workspace: PinWorkspaceSummary) {
        pinWorkspaceRenameText = pinWorkspaceRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try onRenamePinWorkspace(workspace, pinWorkspaceRenameText)
            pinWorkspaceStatusMessage = L10n.text("pinWorkspace.renamedMessage", pinWorkspaceRenameText)
            pinWorkspaceStatusIsError = false
            pinWorkspaceStore.refresh()
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
        pinWorkspacePendingRename = nil
        pinWorkspaceRenameText = ""
    }

    private func duplicatePinWorkspace(_ workspace: PinWorkspaceSummary) {
        let candidateName = pinWorkspaceDuplicateText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let duplicated = try onDuplicatePinWorkspace(workspace, candidateName.isEmpty ? nil : candidateName)
            pinWorkspaceStore.refresh()
            pinWorkspaceStatusMessage = L10n.text(
                "pinWorkspace.duplicatedMessage",
                duplicated.name,
                duplicated.pinCount
            )
            pinWorkspaceStatusIsError = false
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
        pinWorkspacePendingDuplicate = nil
        pinWorkspaceDuplicateText = ""
    }

    private func exportPinWorkspace(_ workspace: PinWorkspaceSummary, format: PinWorkspaceExportFormat) {
        do {
            let report = try onExportPinWorkspace(workspace, format)
            pinWorkspaceStatusIsError = false
            if let report {
                pinWorkspaceStatusMessage = L10n.text(
                    "pinWorkspace.exportSuccess",
                    report.destinationURL.lastPathComponent,
                    report.exportedPinCount,
                    report.skippedPinCount
                )
            } else {
                pinWorkspaceStatusMessage = L10n.text("pinWorkspace.exportNoFile")
            }
            loadPinWorkspaceStorageMetrics()
        } catch {
            pinWorkspaceStatusMessage = error.localizedDescription
            pinWorkspaceStatusIsError = true
        }
    }

    @ViewBuilder
    private func pinWorkspaceRenameSheet(for workspace: PinWorkspaceSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("pinWorkspace.renameTitle"))
                .font(.title2.bold())
            TextField(L10n.text("pinWorkspace.namePlaceholder"), text: $pinWorkspaceRenameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    renamePinWorkspace(workspace)
                }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    pinWorkspacePendingRename = nil
                }
                Button(L10n.text("common.save")) {
                    renamePinWorkspace(workspace)
                }
                .disabled(pinWorkspaceRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420, height: 170)
    }

    @ViewBuilder
    private func pinWorkspaceDuplicateSheet(for workspace: PinWorkspaceSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("pinWorkspace.duplicateTitle"))
                .font(.title2.bold())
            Text(L10n.text("pinWorkspace.duplicateHelp", workspace.name))
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(L10n.text("pinWorkspace.duplicatePlaceholder"), text: $pinWorkspaceDuplicateText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    duplicatePinWorkspace(workspace)
                }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    pinWorkspacePendingDuplicate = nil
                }
                Button(L10n.text("common.save")) {
                    duplicatePinWorkspace(workspace)
                }
            }
        }
        .padding(22)
        .frame(width: 450, height: 210)
    }

    private var selectedOCRPlugin: OCRPluginManifest? {
        ocrPlugins.first { $0.id == ocrProviderID }
    }

    private var ocrTab: some View {
        Form {
            Section(L10n.text("ocr.preferences.providerSection")) {
                Picker(L10n.text("ocr.preferences.provider"), selection: $ocrProviderID) {
                    Text(L10n.text("ocr.preferences.localProvider"))
                        .tag(OCRPluginConstants.localProviderID)
                    ForEach(ocrPlugins) { plugin in
                        Text(plugin.name).tag(plugin.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: ocrProviderID) { _, _ in loadSelectedOCRPluginConfiguration() }

                Text(L10n.text(
                    ocrProviderID == OCRPluginConstants.localProviderID
                        ? "ocr.preferences.localHelp"
                        : "ocr.preferences.remoteHelp"
                ))
                .foregroundStyle(.secondary)

                if ocrProviderID == OCRPluginConstants.localProviderID {
                    Button(L10n.text("common.save"), action: saveOCRConfiguration)
                }
            }

            if ocrProviderID != OCRPluginConstants.localProviderID {
                Section(L10n.text("ocr.preferences.connectionSection")) {
                    if selectedOCRPlugin == nil {
                        Text(L10n.text("ocr.preferences.pluginUnavailable"))
                            .foregroundStyle(.red)
                    }
                    TextField(L10n.text("ocr.preferences.baseURL"), text: $ocrBaseURL)
                        .textContentType(.URL)
                    TextField(L10n.text("ocr.preferences.model"), text: $ocrModel)
                    SecureField(
                        ocrHasSavedAPIKey
                            ? L10n.text("ocr.preferences.apiKeySavedPlaceholder")
                            : L10n.text("ocr.preferences.apiKey"),
                        text: $ocrAPIKey
                    )
                    Text(L10n.text("ocr.preferences.keychainHelp"))
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(L10n.text("common.save"), action: saveOCRConfiguration)
                            .disabled(selectedOCRPlugin == nil)
                        if ocrHasSavedAPIKey {
                            Button(L10n.text("ocr.preferences.removeAPIKey"), role: .destructive) {
                                removeOCRAPIKey()
                            }
                        }
                    }
                }
            }

            Section(L10n.text("ocr.preferences.pluginsSection")) {
                HStack {
                    Button(L10n.text("ocr.preferences.openPluginsFolder"), action: openOCRPluginsFolder)
                    Button(L10n.text("ocr.preferences.reloadPlugins"), action: reloadOCRPlugins)
                }
                Text(L10n.text("ocr.preferences.pluginsHelp"))
                    .foregroundStyle(.secondary)
                if !ocrPluginLoadErrors.isEmpty {
                    Text(L10n.text("ocr.preferences.loadErrors", ocrPluginLoadErrors.count))
                        .foregroundStyle(.orange)
                        .help(ocrPluginLoadErrors.joined(separator: "\n"))
                }
            }

            if let ocrStatusMessage {
                Section {
                    Text(ocrStatusMessage)
                        .foregroundStyle(ocrStatusIsError ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear {
            reloadOCRPlugins()
            loadSelectedOCRPluginConfiguration()
        }
    }

    private func reloadOCRPlugins() {
        let result = OCRPluginCatalog.load()
        ocrPlugins = result.plugins
        ocrPluginLoadErrors = result.errors
        loadSelectedOCRPluginConfiguration()
    }

    private func loadSelectedOCRPluginConfiguration() {
        ocrStatusMessage = nil
        ocrStatusIsError = false
        ocrAPIKey = ""
        guard let plugin = selectedOCRPlugin else {
            ocrBaseURL = ""
            ocrModel = ""
            ocrHasSavedAPIKey = false
            return
        }
        let configuration = OCRPluginSettings.configuration(for: plugin)
        ocrBaseURL = configuration.baseURL
        ocrModel = configuration.model
        ocrHasSavedAPIKey = (try? OCRPluginCredentialStore.hasAPIKey(pluginID: plugin.id)) == true
    }

    private func saveOCRConfiguration() {
        do {
            if ocrProviderID == OCRPluginConstants.localProviderID {
                OCRPluginSettings.save(providerID: ocrProviderID, configuration: nil)
            } else {
                guard let plugin = selectedOCRPlugin else { throw OCRPluginError.pluginNotFound }
                let configuration = OCRPluginConfiguration(
                    baseURL: ocrBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: ocrModel.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let enteredAPIKey = ocrAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                try OCRPluginRequestBuilder.validate(
                    manifest: plugin,
                    configuration: configuration,
                    hasAPIKey: !enteredAPIKey.isEmpty || ocrHasSavedAPIKey
                )
                if !enteredAPIKey.isEmpty {
                    try OCRPluginCredentialStore.saveAPIKey(enteredAPIKey, pluginID: plugin.id)
                }
                OCRPluginSettings.save(providerID: plugin.id, configuration: configuration)
                ocrAPIKey = ""
                ocrHasSavedAPIKey = try OCRPluginCredentialStore.hasAPIKey(pluginID: plugin.id)
            }
            ocrStatusMessage = L10n.text("ocr.preferences.saved")
            ocrStatusIsError = false
        } catch {
            ocrStatusMessage = error.localizedDescription
            ocrStatusIsError = true
        }
    }

    private func removeOCRAPIKey() {
        guard let plugin = selectedOCRPlugin else { return }
        do {
            try OCRPluginCredentialStore.deleteAPIKey(pluginID: plugin.id)
            ocrAPIKey = ""
            ocrHasSavedAPIKey = false
            ocrStatusMessage = L10n.text("ocr.preferences.apiKeyRemoved")
            ocrStatusIsError = false
        } catch {
            ocrStatusMessage = error.localizedDescription
            ocrStatusIsError = true
        }
    }

    private func openOCRPluginsFolder() {
        do {
            let directory = try OCRPluginCatalog.createPluginsDirectory()
            NSWorkspace.shared.open(directory)
            ocrStatusMessage = nil
            ocrStatusIsError = false
        } catch {
            ocrStatusMessage = error.localizedDescription
            ocrStatusIsError = true
        }
    }

    private var privacyTab: some View {
        Form {
            Section(L10n.text("preferences.screenCapturePermission")) {
                HStack {
                    Label(
                        L10n.text(appHealth.screenCapturePermissionGranted ? "preferences.permissionGranted" : "preferences.permissionMissing"),
                        systemImage: appHealth.screenCapturePermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(appHealth.screenCapturePermissionGranted ? .green : .orange)
                    Spacer()
                    if !appHealth.screenCapturePermissionGranted {
                        Button(L10n.text("onboarding.requestPermission"), action: onRequestScreenCapturePermission)
                    }
                    Button(L10n.text("permission.openSettings"), action: onOpenScreenCaptureSettings)
                }
                Text(L10n.text("preferences.permissionHelp"))
                    .foregroundStyle(.secondary)
                Button(L10n.text("preferences.copyDiagnostics")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(CaptureDiagnostics.report(), forType: .string)
                }
                Text(L10n.text("preferences.diagnosticsHelp"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("preferences.languageSection")) {
                Picker(L10n.text("preferences.language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }
            Section(L10n.text("preferences.launch")) {
                Toggle(
                    L10n.text("preferences.launchAtLogin"),
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )
                if launchAtLoginManager.state == .requiresApproval {
                    Button(L10n.text("preferences.openLoginSettings")) { launchAtLoginManager.openSystemSettings() }
                }
                if let message = launchAtLoginManager.message {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            Section(L10n.text("preferences.trayIcon")) {
                TimelineView(.periodic(from: .now, by: TrayIconChoice.animationInterval)) { context in
                    VStack(alignment: .leading, spacing: 12) {
                        trayIconGrid(
                            title: L10n.text("preferences.trayIcon.monochrome"),
                            choices: TrayIconChoice.monochromeChoices,
                            date: context.date
                        )
                        trayIconGrid(
                            title: L10n.text("preferences.trayIcon.color"),
                            choices: TrayIconChoice.colorChoices,
                            date: context.date
                        )
                    }
                }
                Text(L10n.text("preferences.trayIconHelp"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("preferences.capture")) {
                Picker(L10n.text("preferences.outputQuality"), selection: captureQualityBinding) {
                    ForEach(CaptureQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.menu)
                Toggle(L10n.text("preferences.includeCursor"), isOn: $captureCursor)
                Toggle(L10n.text("preferences.captureAnimation"), isOn: $captureEntranceAnimation)
                Toggle(L10n.text("preferences.quickCaptureOverlay"), isOn: $quickCaptureOverlayEnabled)
                Text(L10n.text("preferences.quickCaptureOverlayHelp"))
                    .foregroundStyle(.secondary)
                Toggle(L10n.text("preferences.allowDarkCaptures"), isOn: $allowUniformDarkCaptures)
                Text(L10n.text("preferences.allowDarkCapturesHelp"))
                    .foregroundStyle(.secondary)
                Text(L10n.text("preferences.qualityHelp"))
                    .foregroundStyle(.secondary)
                if selectedCaptureQuality == .uhd8K {
                    Text(L10n.text("preferences.8kWarning"))
                        .foregroundStyle(.orange)
                }
            }
            Section(L10n.text("preferences.updates")) {
                Toggle(
                    L10n.text("preferences.automaticallyCheckForUpdates"),
                    isOn: automaticUpdateChecksBinding
                )
                Picker(
                    L10n.text("preferences.updateCheckFrequency"),
                    selection: updateCheckFrequencyBinding
                ) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!updateManager.automaticallyChecksForUpdates)
                Text(L10n.text("preferences.updateCheckHelp"))
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("preferences.privacy")) {
                Toggle(L10n.text("preferences.clearOnQuit"), isOn: $clearHistoryOnQuit)
                Text(L10n.text("preferences.localOnly"))
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("preferences.pinOperations")) {
                Toggle(L10n.text("preferences.pinShadow"), isOn: $pinWindowShadow)
                    .onChange(of: pinWindowShadow) { _, enabled in onPinShadowChanged(enabled) }
                Text(L10n.text("preferences.pinHelp"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(PreferencesSwitchToggleStyle())
        .padding(12)
        .onAppear {
            launchAtLoginManager.refresh()
            updateManager.refreshSettings()
        }
    }

    private var toolbarTab: some View {
        Form {
            Section(L10n.text("preferences.selectionToolbar.configuration")) {
                ForEach(Array(toolbarConfiguredActionOrder.enumerated()), id: \.element.rawValue) { index, action in
                    HStack(spacing: 10) {
                        Image(systemName: action.symbolName())
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 24, height: 24)

                        Text(L10n.text(action.titleKey))
                            .frame(width: 160, alignment: .leading)

                        if toolbarRequiredActions.contains(action) {
                            Text(L10n.text("preferences.selectionToolbar.required"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: toolbarVisibilityBinding(for: action)
                        )
                        .disabled(toolbarRequiredActions.contains(action))

                        Button {
                            moveToolbarAction(action, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .help(L10n.text("preferences.selectionToolbar.moveUp"))
                        .accessibilityLabel(L10n.text("preferences.selectionToolbar.moveUp"))

                        Button {
                            moveToolbarAction(action, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == toolbarConfiguredActionOrder.count - 1)
                        .help(L10n.text("preferences.selectionToolbar.moveDown"))
                        .accessibilityLabel(L10n.text("preferences.selectionToolbar.moveDown"))
                    }
                    .padding(.vertical, 4)
                }

                Toggle(
                    L10n.text("preferences.selectionToolbar.autoSort"),
                    isOn: Binding(
                        get: { toolbarAutoSort },
                        set: { enabled in
                            toolbarAutoSort = enabled
                            SelectionToolbarConfiguration.setAutomaticallySortsByUsage(enabled, defaults: UserDefaults.standard)
                        }
                    )
                )
                Text(L10n.text("preferences.selectionToolbar.autoSortHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.text("preferences.selectionToolbar.visibilityHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("preferences.selectionToolbarIcons")) {
                ForEach(SelectionToolbarAction.allCases.filter { $0 != .annotate }, id: \.rawValue) { action in
                    SelectionToolbarIconField(action: action)
                }
                Text(L10n.text("preferences.selectionToolbarIconsHelp"))
                    .foregroundStyle(.secondary)
            }

            Button(L10n.text("preferences.selectionToolbar.reset")) {
                resetToolbarConfiguration()
            }
            .padding(.top, 6)
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear {
            refreshToolbarConfiguration()
        }
    }

    private var toolbarRequiredActions: Set<SelectionToolbarAction> {
        SelectionToolbarAction.requiredActions
    }

    private var toolbarConfiguredActionOrder: [SelectionToolbarAction] {
        let configured = SelectionToolbarAction.configurableActions
        var ordered: [SelectionToolbarAction] = []
        for action in toolbarActionOrder where configured.contains(action) && !ordered.contains(action) {
            ordered.append(action)
        }
        for action in configured where !ordered.contains(action) {
            ordered.append(action)
        }
        return ordered
    }

    private func toolbarVisibilityBinding(for action: SelectionToolbarAction) -> Binding<Bool> {
        Binding(
            get: {
                if toolbarRequiredActions.contains(action) {
                    return true
                }
                return toolbarVisibleActions[action.rawValue, default: false]
            },
            set: { isVisible in
                guard !toolbarRequiredActions.contains(action) else { return }
                toolbarVisibleActions[action.rawValue] = isVisible
                SelectionToolbarConfiguration.setVisible(isVisible, for: action, defaults: UserDefaults.standard)
            }
        )
    }

    private func refreshToolbarConfiguration() {
        toolbarActionOrder = SelectionToolbarConfiguration.manualOrder(defaults: UserDefaults.standard)
        toolbarVisibleActions = Dictionary(
            uniqueKeysWithValues: SelectionToolbarConfiguration.visibleActions(defaults: UserDefaults.standard)
                .map { action in
                    (action.rawValue, true)
                }
        )
        toolbarAutoSort = SelectionToolbarConfiguration.automaticallySortsByUsage(defaults: UserDefaults.standard)
        for action in toolbarRequiredActions {
            toolbarVisibleActions[action.rawValue] = true
            SelectionToolbarConfiguration.setVisible(true, for: action, defaults: UserDefaults.standard)
        }
    }

    private func moveToolbarAction(_ action: SelectionToolbarAction, direction: Int) {
        guard let currentIndex = toolbarConfiguredActionOrder.firstIndex(of: action) else {
            return
        }
        let nextIndex = currentIndex + direction
        guard toolbarConfiguredActionOrder.indices.contains(nextIndex) else {
            return
        }
        var reordered = toolbarConfiguredActionOrder
        let moving = reordered.remove(at: currentIndex)
        reordered.insert(moving, at: nextIndex)
        toolbarActionOrder = reordered
        SelectionToolbarConfiguration.setManualOrder(reordered, defaults: UserDefaults.standard)
    }

    private func resetToolbarConfiguration() {
        for action in SelectionToolbarAction.allCases {
            UserDefaults.standard.removeObject(forKey: action.iconDefaultsKey)
        }
        SelectionToolbarConfiguration.reset(defaults: UserDefaults.standard)
        refreshToolbarConfiguration()
    }

    private var watermarkTab: some View {
        Form {
            Section(L10n.text("watermark.preferences.section")) {
                Toggle(L10n.text("watermark.preferences.enabled"), isOn: $invisibleWatermarkEnabled)
                Text(L10n.text("watermark.preferences.enabledHelp"))
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("watermark.preferences.details")) {
                TextField(L10n.text("watermark.preferences.project"), text: $watermarkProject)
                    .disabled(!invisibleWatermarkEnabled)
                TextField(L10n.text("watermark.preferences.recipient"), text: $watermarkRecipient)
                    .disabled(!invisibleWatermarkEnabled)
                TextField(L10n.text("watermark.preferences.customText"), text: $watermarkCustomText, axis: .vertical)
                    .lineLimit(2...4)
                    .disabled(!invisibleWatermarkEnabled)
                Text(L10n.text("watermark.preferences.privacyPreview"))
                    .foregroundStyle(.secondary)
            }
            Section(L10n.text("watermark.preferences.localRecords")) {
                Text(L10n.text("watermark.preferences.recordCount", watermarkStore.records.count))
                Button(L10n.text("watermark.preferences.clearRecords"), role: .destructive) {
                    isConfirmingWatermarkClear = true
                }
                .disabled(watermarkStore.records.isEmpty)
                if let watermarkErrorMessage {
                    Text(watermarkErrorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(PreferencesSwitchToggleStyle())
        .padding(12)
        .confirmationDialog(
            L10n.text("watermark.preferences.clearConfirmTitle"),
            isPresented: $isConfirmingWatermarkClear,
            titleVisibility: .visible
        ) {
            Button(L10n.text("watermark.preferences.clearRecords"), role: .destructive) {
                do {
                    try watermarkStore.clear()
                    watermarkErrorMessage = nil
                } catch {
                    watermarkErrorMessage = L10n.text("watermark.preferences.clearFailed", error.localizedDescription)
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("watermark.preferences.clearConfirmMessage"))
        }
    }

    private var selectedCaptureQuality: CaptureQuality {
        CaptureQuality(rawValue: captureQualityRawValue) ?? .defaultValue
    }

    private var selectedTrayIcon: TrayIconChoice {
        TrayIconChoice(rawValue: trayIconRawValue) ?? .defaultChoice
    }

    private func trayIconGrid(title: String, choices: [TrayIconChoice], date: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(choices) { choice in
                    trayIconButton(choice, date: date)
                }
            }
        }
    }

    private func trayIconButton(_ choice: TrayIconChoice, date: Date) -> some View {
        let frameIndex = accessibilityReduceMotion ? 0 : choice.frameIndex(at: date)
        let iconColor = choice.color(frameIndex: frameIndex).map(Color.init(nsColor:)) ?? .primary
        let isSelected = selectedTrayIcon == choice
        let displayedIconColor: Color = isSelected && !choice.usesColor ? .accentColor : iconColor
        return Button {
            trayIconRawValue = choice.rawValue
            onTrayIconChanged(choice)
        } label: {
            trayIconPreview(
                choice,
                frameIndex: frameIndex,
                displayedIconColor: displayedIconColor
            )
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(Color.accentColor)
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 14, height: 14)
                        .offset(x: 4, y: -4)
                    }
                }
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.22) : .clear,
                    radius: 3,
                    y: 1
                )
        }
        .buttonStyle(TrayIconChoiceButtonStyle())
        .help(choice.title)
        .accessibilityLabel(choice.title)
    }

    @ViewBuilder
    private func trayIconPreview(
        _ choice: TrayIconChoice,
        frameIndex: Int,
        displayedIconColor: Color
    ) -> some View {
        if choice.usesCustomArtwork,
           let image = choice.statusBarImage(frameIndex: frameIndex) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: choice.symbolName(frameIndex: frameIndex))
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(displayedIconColor)
        }
    }

    private var captureQualityBinding: Binding<CaptureQuality> {
        Binding(
            get: { selectedCaptureQuality },
            set: { captureQualityRawValue = $0.rawValue }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { localizationStore.language },
            set: { localizationStore.setLanguage($0) }
        )
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var updateCheckFrequencyBinding: Binding<UpdateCheckFrequency> {
        Binding(
            get: { updateManager.checkFrequency },
            set: { updateManager.setCheckFrequency($0) }
        )
    }
}

private struct PreferencesSwitchToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                PreferencesSwitch(isOn: configuration.isOn, isEnabled: isEnabled)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.16),
            value: configuration.isOn
        )
    }
}

private struct PreferencesSwitch: View {
    let isOn: Bool
    let isEnabled: Bool

    var body: some View {
        Capsule()
            .fill(trackColor)
            .frame(width: 52, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.16), radius: 2, y: 1)
            }
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 0.5)
            }
            .opacity(isEnabled ? 1 : 0.46)
    }

    private var trackColor: Color {
        isOn ? Color.accentColor : Color.secondary.opacity(0.28)
    }
}

private struct HistoryThumbnailView: View {
    @ObservedObject var historyStore: HistoryStore
    let item: HistoryItem
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.06))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 76, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: item.id) {
            thumbnail = nil
            thumbnail = await historyStore.thumbnail(for: item)
        }
    }
}

private struct SelectionToolbarIconField: View {
    let action: SelectionToolbarAction
    @AppStorage private var symbolName: String

    init(action: SelectionToolbarAction) {
        self.action = action
        _symbolName = AppStorage(wrappedValue: "", action.iconDefaultsKey)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: visibleSymbolName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 24, height: 24)
            Text(L10n.text(action.titleKey))
                .frame(width: 116, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(action.presetSymbolNames, id: \.self) { candidate in
                    Button {
                        symbolName = candidate == action.defaultSymbolName ? "" : candidate
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(candidate == selectedSymbolName ? Color.accentColor : Color.primary)
                            .frame(width: 36, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(candidate == selectedSymbolName ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(candidate == selectedSymbolName ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                    .accessibilityLabel("\(L10n.text(action.titleKey)) \(candidate)")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var selectedSymbolName: String {
        let stored = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? action.defaultSymbolName : stored
    }

    private var visibleSymbolName: String {
        NSImage(systemSymbolName: selectedSymbolName, accessibilityDescription: nil) == nil
            ? "questionmark.square"
            : selectedSymbolName
    }
}

private struct TrayIconChoiceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                accessibilityReduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

private struct PreferencesSidebarButton: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let section: PreferencesSection
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? section.tint : Color.secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        section.tint.opacity(isSelected ? 0.14 : isHovering ? 0.09 : 0),
                        in: RoundedRectangle(cornerRadius: 7)
                    )

                Text(section.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(section.tint.opacity(0.11))
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.045))
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(section.tint)
                        .frame(width: 3, height: 21)
                        .offset(x: 2)
                        .matchedGeometryEffect(id: "preferences-sidebar-selection", in: selectionNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
    }
}

/// 收集“动作 + 按键组合”，成功写入后由父视图统一重注册全局快捷键。
private struct AddShortcutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (CaptureAction, Shortcut) -> Bool

    @State private var selectedAction: CaptureAction = .region
    @State private var shortcut = Shortcut(keyCode: UInt32(kVK_F4), carbonModifiers: 0)
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("preferences.addShortcut")).font(.title2.bold())

            Picker(L10n.text("preferences.triggerAction"), selection: $selectedAction) {
                ForEach(CaptureAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }

            HStack {
                Text(L10n.text("preferences.keyCombination"))
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut) { shortcut = $0 }
                    .frame(width: 140, height: 28)
            }

            Text(L10n.text("preferences.recordHelp"))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            Spacer()
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) { dismiss() }
                Button(L10n.text("common.add")) {
                    if onAdd(selectedAction, shortcut) {
                        dismiss()
                    } else {
                        errorMessage = L10n.text("preferences.shortcutConflict")
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400, height: 250)
    }
}

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: shortcut.displayText, target: context.coordinator, action: #selector(Coordinator.beginRecording(_:)))
        button.bezelStyle = .rounded
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        if context.coordinator.monitor == nil { button.title = shortcut.displayText }
        context.coordinator.onChange = onChange
    }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Shortcut) -> Void
        weak var button: NSButton?
        var monitor: Any?
        private var idleTitle = ""

        init(onChange: @escaping (Shortcut) -> Void) { self.onChange = onChange }

        @objc func beginRecording(_ sender: NSButton) {
            stopRecording()
            idleTitle = sender.title
            sender.title = L10n.text("preferences.pressShortcut")
            sender.setAccessibilityHelp(L10n.text("preferences.recordHelp"))
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == UInt16(kVK_Escape) {
                    self.stopRecording()
                    return nil
                }
                let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
                guard shortcut.isSafeGlobalShortcut else {
                    NSSound.beep()
                    self.button?.title = L10n.text("preferences.shortcutUnsafe")
                    self.button?.setAccessibilityValue(L10n.text("preferences.shortcutUnsafe"))
                    return nil
                }
                self.onChange(shortcut)
                self.button?.title = shortcut.displayText
                self.button?.setAccessibilityValue(shortcut.displayText)
                self.stopRecording(restoreTitle: false)
                return nil
            }
        }

        func stopRecording(restoreTitle: Bool = true) {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if restoreTitle, !idleTitle.isEmpty {
                button?.title = idleTitle
                button?.setAccessibilityValue(idleTitle)
            }
        }
    }
}
