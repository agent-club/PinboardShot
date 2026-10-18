import AppKit
import BrowserCaptureBridge
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

private enum HistoryManagementPane: Int, Identifiable {
    case saving, exclusions, storage
    var id: Int { rawValue }
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

    var railTitle: String { L10n.text("settings.rail.\(rawValue)") }

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
    @Environment(\.colorScheme) private var colorScheme
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
    var onEditHistoryItem: (HistoryItem) -> Void = { _ in }
    var onHistoryTools: (HistoryItem) -> Void = { _ in }
    var onPrepareBrowserExtension: () -> Void = {}
    var onDownloadBrowserExtension: () -> Void = {}
    var onStartBrowserCapture: () -> Void = {}

    @AppStorage(EditableDraftSettings.enabledKey) private var editableDraftsEnabled = false
    @AppStorage(AppAppearance.userDefaultsKey) private var appAppearance = AppAppearance.system

    @AppStorage("captureCursor") private var captureCursor = false
    @AppStorage(OverlaySafetyPolicy.alwaysOnTopDefaultsKey) private var captureSelectionAlwaysOnTop =
        true
    @AppStorage(CaptureQuality.userDefaultsKey)
    private var captureQualityRawValue = CaptureQuality.defaultValue.rawValue
    @AppStorage("clearHistoryOnQuit") private var clearHistoryOnQuit = false
    @AppStorage(OverlaySafetyPolicy.animationDefaultsKey) private var captureEntranceAnimation = true
    @AppStorage(CaptureImageValidator.allowUniformDarkDefaultsKey) private
        var allowUniformDarkCaptures = false
    @AppStorage(PinWindowManager.shadowDefaultsKey) private var pinWindowShadow = true
    @AppStorage(QuickCaptureOverlaySettings.enabledDefaultsKey) private
        var quickCaptureOverlayEnabled = true
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
    @State private var toolbarActionOrder: [SelectionToolbarAction] =
        SelectionToolbarConfiguration.manualOrder(defaults: UserDefaults.standard)
    @State private var toolbarVisibleActions: [String: Bool] = Dictionary(
        uniqueKeysWithValues: SelectionToolbarConfiguration.visibleActions(
            defaults: UserDefaults.standard
        )
        .map { action in
            (action.rawValue, true)
        }
    )
    @State private var toolbarAutoSort: Bool =
        SelectionToolbarConfiguration.automaticallySortsByUsage(defaults: UserDefaults.standard)
    @State private var historyManagementPane: HistoryManagementPane?
    @State private var workspacePane = 0
    @State private var generalPane = 0
    @State private var toolbarPane = 0
    @State private var selectedHistoryID: UUID?
    @State private var historyKeptOnly = false
    @State private var selectedWorkspaceID: UUID?
    @State private var isSavingWorkspace = false
    @State private var ocrPane = 0
    @FocusState private var historyListFocused: Bool

    private var selectedSection: PreferencesSection { navigation.selectedSection }

    var body: some View {
        HStack(spacing: 0) {
            preferencesSidebar
            Divider()
            preferencesContent
        }
        .frame(minWidth: PreferencesWindowMetrics.width, minHeight: PreferencesWindowMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var preferencesSidebar: some View {
        VStack(spacing: 5) {
            ForEach(PreferencesSection.allCases) { section in
                PreferencesSidebarButton(
                    section: section, isSelected: selectedSection == section,
                    action: { select(section) })
            }
            Spacer(minLength: 8)
            Circle().fill(appHealth.isReady ? Color.secondary : Color.orange)
                .frame(width: 5, height: 5)
                .help(L10n.text(appHealth.isReady ? "menu.ready" : "preferences.healthNeedsAttention"))
                .accessibilityLabel(L10n.text(appHealth.isReady ? "menu.ready" : "preferences.healthNeedsAttention"))
                .padding(.bottom, 12)
        }
        .padding(.top, 12).frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var preferencesContent: some View {
        VStack(spacing: 0) {
            if selectedSection != .history && selectedSection != .pins {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: selectedSection.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.07)))
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedSection.title).font(.system(size: 18, weight: .semibold))
                        Text(L10n.text("settings.description.\(selectedSection.rawValue)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    pageHeaderAction
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
                .frame(maxWidth: selectedSection == .shortcuts ? 696 : 776, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            selectedContent
                .id(selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background {
            if selectedSection == .history || selectedSection == .pins {
                Color(nsColor: .textBackgroundColor)
            } else {
                colorScheme == .dark ? Color(white: 0.105) : Color(white: 0.955)
            }
        }
        .font(.system(size: 12))
        .toggleStyle(PreferencesRowToggleStyle())
        .labeledContentStyle(PreferencesFieldStyle())
        .controlSize(.small)
        .tint(Color(nsColor: .labelColor))
    }

    @ViewBuilder
    private var pageHeaderAction: some View {
        switch selectedSection {
        case .shortcuts:
            Button {
                isAddingShortcut = true
            } label: {
                Label(L10n.text("preferences.addShortcut"), systemImage: "plus")
            }.clickCursor().buttonStyle(.borderedProminent)
        case .history:
            Button {
                onCreateBoard()
            } label: {
                Label(L10n.text("composition.create"), systemImage: "rectangle.3.group")
            }.clickCursor()
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
        PreferencesPage(maximumWidth: 640) {
            PreferencesGroup(L10n.text("settings.shortcuts.actions"), spacing: 0) {
                if shortcutStore.bindings.isEmpty {
                    PreferencesEmptyState(symbol: "keyboard", title: L10n.text("settings.shortcuts.empty"),
                        message: L10n.text("preferences.recordHelp"))
                } else {
                    ForEach(shortcutStore.bindings) { binding in
                        HStack(spacing: 12) {
                            Image(systemName: "command")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(binding.action.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
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
                            .frame(width: 108, height: 30)

                            Button(role: .destructive) {
                                shortcutStore.remove(bindingID: binding.id)
                                shortcutMessage = nil
                                onShortcutsChanged()
                            } label: {
                                Image(systemName: "minus.circle")
                            }.clickCursor()
                                .buttonStyle(.borderless)
                                .help(L10n.text("preferences.deleteShortcut"))
                        }
                        .padding(.vertical, 8)
                        if binding.id != shortcutStore.bindings.last?.id { Divider() }
                    }
                }
                Divider().padding(.top, 6).padding(.bottom, 12)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).padding(.top, 2)
                    Text(L10n.text("preferences.shortcutHelp"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(L10n.text("preferences.restoreShortcuts")) {
                        shortcutStore.reset()
                        onShortcutsChanged()
                    }.clickCursor().controlSize(.small)
                        .disabled(shortcutStore.bindings.isEmpty)
                }
                if let shortcutMessage {
                    Label(shortcutMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red).font(.system(size: 11)).padding(.top, 12)
                }
            }
        }
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
        VStack(spacing: 0) {
            if let message = historyErrorMessage ?? historyStore.retentionErrorMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            HStack(spacing: 0) {
                historyList
                Divider()
                historyPreview
            }
        }
        .sheet(item: $historyManagementPane) { pane in
            historyManagement(pane: pane.rawValue)
        }
        .sheet(item: $selectedHistoryItemForDetail) { item in
            historyItemDetailSheet(for: item)
        }
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(PreferencesSection.history.title).font(.system(size: 16, weight: .semibold))
                Picker("", selection: $historyKeptOnly) {
                    Text(L10n.text("history.cleanupAll")).tag(false)
                    Text(L10n.text("settings.history.starred")).tag(true)
                }.labelsHidden().pickerStyle(.segmented)
                PreferencesSearchField(placeholder: L10n.text("preferences.historySearch"), text: $historySearch)
                    .help(L10n.text("history.searchHelp"))
            }.padding(14)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredHistoryItems) { item in
                            historyListRow(item).id(item.id)
                        }
                    }.padding(.horizontal, 6)
                }
                .onChange(of: selectedHistoryID) { _, value in
                    if let value { withAnimation { proxy.scrollTo(value, anchor: .center) } }
                }
            }
            Divider()
            HStack(spacing: 6) {
                Text(L10n.text("settings.history.results", filteredHistoryItems.count))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Menu {
                    ForEach(0..<3) { index in
                        Button(L10n.text(["settings.history.saving", "history.applicationExclusions", "settings.history.maintenance"][index])) {
                            historyManagementPane = HistoryManagementPane(rawValue: index)
                        }
                    }
                    Divider()
                    Button(L10n.text("composition.create"), action: onCreateBoard)
                        .disabled(historyStore.items.isEmpty)
                } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 28)
                }.menuStyle(.borderlessButton).fixedSize()
                    .help(L10n.text("settings.history.manage"))
                    .accessibilityLabel(L10n.text("settings.history.manage"))
            }.padding(.horizontal, 14).frame(height: 42)
        }
        .frame(width: 224)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .focusable().focusEffectDisabled().focused($historyListFocused)
        .onMoveCommand { direction in
            guard direction == .up || direction == .down, !filteredHistoryItems.isEmpty else { return }
            let index = filteredHistoryItems.firstIndex { $0.id == selectedHistoryItem?.id } ?? 0
            let next = min(max(0, index + (direction == .down ? 1 : -1)), filteredHistoryItems.count - 1)
            selectedHistoryID = filteredHistoryItems[next].id
        }
    }

    private func historyListRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 5) {
            Button {
                selectedHistoryID = item.id
                historyListFocused = true
            } label: {
                HStack(spacing: 9) {
                    HistoryThumbnailView(historyStore: historyStore, item: item)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.createdAt, style: .date).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(item.createdAt, style: .time).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("\(item.pixelWidth) × \(item.pixelHeight)")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { setHistoryItemKept(item, kept: !item.isKept) } label: {
                Image(systemName: item.isKept ? "star.fill" : "star")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
            }.buttonStyle(.plain)
                .help(L10n.text(item.isKept ? "history.unkeep" : "history.keep"))
                .accessibilityLabel(L10n.text(item.isKept ? "history.unkeep" : "history.keep"))
        }
        .padding(.horizontal, 7).frame(height: 60)
        .background(selectedHistoryItem?.id == item.id ? Color.primary.opacity(0.065) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            if selectedHistoryItem?.id == item.id {
                RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.55)).frame(width: 2, height: 34)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(
                selectedHistoryItem?.id == item.id && historyListFocused
                    ? Color.primary.opacity(0.22) : .clear,
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
        .contextMenu { historyActions(item) }
    }

    private var selectedHistoryItem: HistoryItem? {
        filteredHistoryItems.first { $0.id == selectedHistoryID } ?? filteredHistoryItems.first
    }

    @ViewBuilder
    private var historyPreview: some View {
        if let item = selectedHistoryItem {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.createdAt, style: .date).font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 8) {
                            Text(item.createdAt, style: .time)
                            Text("\(item.pixelWidth) × \(item.pixelHeight)")
                            let source = historyApplicationName(for: item.sourceApplicationBundleIdentifier)
                            if !source.isEmpty { Text(source).lineLimit(1) }
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { setHistoryItemKept(item, kept: !item.isKept) } label: {
                        Image(systemName: item.isKept ? "star.fill" : "star")
                    }.help(L10n.text(item.isKept ? "history.unkeep" : "history.keep"))
                        .accessibilityLabel(L10n.text(item.isKept ? "history.unkeep" : "history.keep"))
                    Menu { historyActions(item) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 25)
                        .accessibilityLabel(L10n.text("settings.moreActions"))
                }.padding(.horizontal, 22).frame(height: 64)
                Divider()
                HistoryPreviewImage(historyStore: historyStore, item: item)
                    .id(item.id).padding(26)
                    .onTapGesture(count: 2) { selectedHistoryItemForDetail = item }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
                Divider()
                HStack(spacing: 8) {
                    Button { onPinHistoryItem(item) } label: {
                        Label(L10n.text("preferences.pinToScreen"), systemImage: "pin")
                    }.buttonStyle(.borderedProminent)
                    Button { onCopyHistoryItem(item) } label: {
                        Label(L10n.text("pin.copy"), systemImage: "doc.on.doc")
                    }
                    Button { onSaveHistoryItem(item) } label: {
                        Label(L10n.text("pin.save"), systemImage: "square.and.arrow.down")
                    }
                    Spacer(minLength: 8)
                    Text(historyOCRStatusText(for: item)).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button { selectedHistoryItemForDetail = item } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }.buttonStyle(.plain).frame(width: 26, height: 28)
                        .help(L10n.text("history.viewDetails"))
                        .accessibilityLabel(L10n.text("history.viewDetails"))
                }.padding(.horizontal, 20).frame(height: 54)
            }
        } else {
            PreferencesEmptyState(
                symbol: historySearch.isEmpty && !historyKeptOnly ? "photo.on.rectangle.angled" : "magnifyingglass",
                title: L10n.text(historyStore.items.isEmpty ? "settings.history.empty" : "settings.search.empty"),
                message: L10n.text(historyStore.items.isEmpty ? "settings.history.emptyHelp" : "settings.search.emptyHelp"))
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func historyActions(_ item: HistoryItem) -> some View {
        Button(L10n.text("pin.copy")) { onCopyHistoryItem(item) }
        Button(L10n.text("preferences.pinToScreen")) { onPinHistoryItem(item) }
        Button(L10n.text("pin.save")) { onSaveHistoryItem(item) }
        Divider()
        Button(L10n.text("feature.draft.edit")) { onEditHistoryItem(item) }
        Button(L10n.text("feature.tools.title")) { onHistoryTools(item) }
        Button(L10n.text("history.viewDetails")) { selectedHistoryItemForDetail = item }
        if item.ocrStatus == .indexed {
            Button(L10n.text("history.copyRecognizedText")) { copyHistoryOCRText(item) }
        }
        if item.ocrStatus == .notIndexed || item.ocrStatus == .empty || item.ocrStatus == .failed {
            Button(L10n.text("history.reindex")) { onReindexHistoryItem(item) }
        }
        Divider()
        Button(L10n.text("preferences.deleteHistoryItem"), role: .destructive) { deleteHistoryItem(item) }
    }

    private func historyManagement(pane: Int) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("settings.history.manage")).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(L10n.text("common.done")) { historyManagementPane = nil }.keyboardShortcut(.cancelAction)
            }.padding(22)
            PreferencesPanePicker(selection: Binding(
                get: { pane },
                set: { historyManagementPane = HistoryManagementPane(rawValue: $0) }
            ), titles: [
                L10n.text("settings.history.saving"), L10n.text("settings.history.exclusions"),
                L10n.text("settings.history.maintenance")])
            PreferencesPage {
                if let message = historyErrorMessage ?? historyStore.retentionErrorMessage {
                    Text(message).foregroundStyle(.red)
                }
                if pane == 0 {
                    PreferencesGroup(L10n.text("settings.history.saving")) {
                        Toggle(L10n.text("preferences.historyEnabled"), isOn: $historyEnabled).clickCursor()
                        Toggle(
                            L10n.text("preferences.pinSessionRecovery.title"), isOn: $pinSessionRecoveryEnabled
                        ).clickCursor()
                            .onChange(of: pinSessionRecoveryEnabled) { _, enabled in
                                onPinSessionRecoveryChanged(enabled)
                            }
                            .help(L10n.text("preferences.pinSessionRecovery.help"))
                        Toggle(L10n.text("preferences.historyOCRIndexing"), isOn: $historyOCRIndexingEnabled)
                            .clickCursor()
                        Toggle(L10n.text("feature.draft.setting"), isOn: $editableDraftsEnabled).clickCursor()
                            .disabled(!historyEnabled)
                            .help(L10n.text("feature.draft.privacy"))

                        HStack {
                            Text(L10n.text("preferences.historyMaximumItems"))
                            Spacer()
                            Picker(L10n.text("preferences.historyMaximumItems"), selection: $historyMaximumItems) {
                                ForEach([10, 25, 50, 100, 250], id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }.clickCursor().pickerStyle(.menu)
                                .labelsHidden().fixedSize()

                        }.frame(minHeight: 32)
                        HStack {
                            Text(L10n.text("preferences.historyRetention"))
                            Spacer()
                            Picker(L10n.text("preferences.historyRetention"), selection: $historyRetentionDays) {
                                Text(L10n.text("preferences.historyRetention.forever")).tag(0)
                                Text(L10n.text("preferences.historyRetention.oneDay")).tag(1)
                                Text(L10n.text("preferences.historyRetention.sevenDays")).tag(7)
                                Text(L10n.text("preferences.historyRetention.thirtyDays")).tag(30)
                                Text(L10n.text("preferences.historyRetention.ninetyDays")).tag(90)
                            }.clickCursor().pickerStyle(.menu)
                                .labelsHidden().fixedSize()

                        }.frame(minHeight: 32)

                        Text(L10n.text("history.keepHelp"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                    }

                } else if pane == 1 {
                    PreferencesGroup(L10n.text("history.applicationExclusions")) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let message = excludedApplicationMessage {
                                Text(message).foregroundStyle(.red).font(.system(size: 10))
                            }
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(excludedApplications) { application in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(historyApplicationName(for: application.bundleIdentifier))
                                                    .lineLimit(1)
                                                Text(application.bundleIdentifier)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button(role: .destructive) {
                                                historyPrivacySettings.remove(
                                                    bundleIdentifier: application.bundleIdentifier)
                                                loadHistoryPrivacyApplications()
                                            } label: {
                                                Image(systemName: "xmark.circle")
                                            }.clickCursor()
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
                                    .font(.system(size: 10))
                            }
                            Button(
                                L10n.text("history.addExcludedApplication"), action: addHistoryExcludedApplication
                            ).clickCursor()
                        }
                    }
                    Text(L10n.text("history.exclusionFailClosedHelp"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                } else {
                    historyStorageOverview
                    PreferencesGroup(L10n.text("history.clearByTime")) {
                        HStack {
                            Picker(L10n.text("history.clearByTime"), selection: $historyCleanupDays) {
                                Text(L10n.text("history.cleanupOneDay")).tag(1)
                                Text(L10n.text("history.cleanupSevenDays")).tag(7)
                                Text(L10n.text("history.cleanupThirtyDays")).tag(30)
                                Text(L10n.text("history.cleanupNinetyDays")).tag(90)
                                Text(L10n.text("history.cleanupAll")).tag(0)
                            }.clickCursor()
                                .pickerStyle(.menu)
                                .help(L10n.text("history.cleanupHelp"))
                            Spacer()
                            Button(L10n.text("history.clearByTime")) {
                                prepareHistoryCleanup()
                            }.clickCursor()
                                .disabled(historyStore.items.isEmpty)
                        }

                        Text(L10n.text("history.cleanupHelp")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    PreferencesGroup(L10n.text("history.clearOCRIndex")) {
                        Text(L10n.text("history.clearOCRIndexHelp")).font(.system(size: 11)).foregroundStyle(.secondary)
                        Button(L10n.text("history.clearOCRIndex"), role: .destructive) {
                            isConfirmingClearOCRIndex = true
                        }.clickCursor()
                    }
                }
            }
        }
        .frame(width: 680, height: 510)
        .font(.system(size: 12)).controlSize(.small)
        .toggleStyle(PreferencesRowToggleStyle()).labeledContentStyle(PreferencesFieldStyle())
        .tint(Color(nsColor: .labelColor))
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
                Text(
                    L10n.text(
                        "history.clearHistoryMessage", preview.itemCount, formatBytes(preview.reclaimableBytes))
                )
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
        .alert(isPresented: $isClearingHistoryItems) {
            Alert(
                title: Text(L10n.text("history.clearHistoryTitle")),
                message: Text(historyClearLabel),
                primaryButton: .default(
                    Text(L10n.text("common.ok")),
                    action: {
                        isClearingHistoryItems = false
                    }),
                secondaryButton: .cancel()
            )
        }

    }

    private var historyStorageOverview: some View {
        PreferencesGroup(L10n.text("settings.history.storage")) {
            HStack(alignment: .firstTextBaseline) {
                if let history = historyStorageMetrics, let pins = pinWorkspaceStorageMetrics {
                    Text(formatBytes(history.totalBytes + pins.totalBytes))
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                }
                Text(L10n.text("settings.history.localStorage")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("history.refreshStorage"), action: loadHistoryStorageMetrics)
            }
            if let history = historyStorageMetrics, let pins = pinWorkspaceStorageMetrics {
                PreferencesStorageBar(segments: [
                    .init(title: L10n.text("settings.storage.images"), bytes: history.imageBytes, shade: 0.75),
                    .init(title: L10n.text("settings.storage.index"), bytes: history.indexBytes, shade: 0.5),
                    .init(title: PreferencesSection.pins.title, bytes: pins.workspaceBytes, shade: 0.3),
                    .init(title: L10n.text("settings.storage.recovery"), bytes: pins.recoveryBytes, shade: 0.15)
                ])
                HStack {
                    Text(L10n.text("history.storageHistory", history.itemCount))
                    Spacer()
                    Text(L10n.text("pinWorkspace.storageWorkspaceCount", pins.workspaceCount))
                    Text(L10n.text("pinWorkspace.storagePins", pins.pinCount))
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let storageMetricsError { Text(storageMetricsError).foregroundStyle(.red) }
        }
    }

    private var pinWorkspacesTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text(PreferencesSection.pins.title).font(.system(size: 18, weight: .semibold))
                Spacer()
                if workspacePane == 0 {
                    Button {
                        pinWorkspaceStatusMessage = nil
                        isSavingWorkspace = true
                    } label: {
                        Label(L10n.text("pinWorkspace.save"), systemImage: "plus")
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal, 24).frame(height: 62)
            PreferencesPanePicker(selection: $workspacePane, titles: [
                L10n.text("pinWorkspace.savedSection"), L10n.text("tray.section.magneticDesktop")])
            if workspacePane == 1 {
                PreferencesPage { MagneticDesktopPreferences() }
            } else {
                HStack(spacing: 0) {
                    workspaceList
                    Divider()
                    workspacePreview
                }.padding(.top, 12)
            }
            if let pinWorkspaceStatusMessage {
                Text(pinWorkspaceStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(pinWorkspaceStatusIsError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $isSavingWorkspace) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("pinWorkspace.saveSection")).font(.system(size: 16, weight: .semibold))
                Text(L10n.text("pinWorkspace.saveHelp")).foregroundStyle(.secondary)
                TextField(L10n.text("pinWorkspace.namePlaceholder"), text: $pinWorkspaceName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitPinWorkspace() }
                if pinWorkspaceStatusIsError, let pinWorkspaceStatusMessage {
                    Text(pinWorkspaceStatusMessage).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button(L10n.text("common.cancel")) { isSavingWorkspace = false }.keyboardShortcut(.cancelAction)
                    Button(L10n.text("pinWorkspace.save")) { submitPinWorkspace() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(pinWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.font(.system(size: 12)).padding(24).frame(width: 390)
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

    private func submitPinWorkspace() {
        guard !pinWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        savePinWorkspace()
        if !pinWorkspaceStatusIsError { isSavingWorkspace = false }
    }

    private var selectedWorkspace: PinWorkspaceSummary? {
        filteredPinWorkspaceStoreItems.first { $0.id == selectedWorkspaceID } ?? filteredPinWorkspaceStoreItems.first
    }

    private var workspaceList: some View {
        VStack(spacing: 12) {
            PreferencesSearchField(placeholder: L10n.text("preferences.search"), text: $pinWorkspaceSearch)
                .padding(.horizontal, 12)
            HStack {
                Text(L10n.text("pinWorkspace.sort")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Picker(L10n.text("pinWorkspace.sort"), selection: $pinWorkspaceSort) {
                    Text(L10n.text("pinWorkspace.sortUpdated")).tag(PinWorkspaceSort.updatedNewest)
                    Text(L10n.text("pinWorkspace.sortName")).tag(PinWorkspaceSort.nameAscending)
                    Text(L10n.text("pinWorkspace.sortRestored")).tag(PinWorkspaceSort.recentlyRestored)
                }.labelsHidden().pickerStyle(.menu).fixedSize()
            }.padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filteredPinWorkspaceStoreItems) { workspace in
                        Button { selectedWorkspaceID = workspace.id } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "rectangle.stack").font(.system(size: 17)).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(workspace.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(L10n.text("pinWorkspace.itemSummary", workspace.pinCount,
                                        formattedHistoryDate(workspace.updatedAt)))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(10).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(selectedWorkspace?.id == workspace.id ? Color.primary.opacity(0.065) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).contextMenu { workspaceActions(workspace) }
                    }
                }.padding(.horizontal, 6)
            }
            if pinWorkspaceStore.loadWarningCount > 0 {
                Text(L10n.text("pinWorkspace.loadWarnings", pinWorkspaceStore.loadWarningCount))
                    .font(.system(size: 10)).foregroundStyle(.orange).padding(12)
            }
        }.padding(.top, 2).frame(width: 224)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    @ViewBuilder
    private var workspacePreview: some View {
        if let workspace = selectedWorkspace {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(workspace.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(L10n.text("pinWorkspace.itemSummary", workspace.pinCount,
                            formattedHistoryDate(workspace.updatedAt)))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu { workspaceActions(workspace) } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 26)
                        .accessibilityLabel(L10n.text("pinWorkspace.moreActions"))
                }.padding(18)
                Divider()
                PreferencesWorkspacePreview(store: pinWorkspaceStore, workspace: workspace).id(workspace)
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
                Divider()
                HStack {
                    Button(L10n.text("pinWorkspace.restore")) { restorePinWorkspace(workspace) }
                        .buttonStyle(.borderedProminent)
                    Menu {
                        Button(L10n.text("pinWorkspace.exportImages")) { exportPinWorkspace(workspace, format: .images) }
                        Button(L10n.text("pinWorkspace.exportPDF")) { exportPinWorkspace(workspace, format: .pdf) }
                        Button(L10n.text("pinWorkspace.exportMarkdown")) { exportPinWorkspace(workspace, format: .markdown) }
                    } label: { Label(L10n.text("settings.workspace.export"), systemImage: "square.and.arrow.up") }
                    Spacer()
                }.padding(.horizontal, 20).frame(height: 54)
                Text(L10n.text("pinWorkspace.privacyHelp")).font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 12)
            }
        } else {
            PreferencesEmptyState(symbol: "rectangle.stack",
                title: L10n.text(pinWorkspaceSearch.isEmpty ? "pinWorkspace.emptyTitle" : "settings.search.empty"),
                message: L10n.text(pinWorkspaceSearch.isEmpty ? "settings.workspace.emptyHelp" : "settings.search.emptyHelp"))
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func workspaceActions(_ workspace: PinWorkspaceSummary) -> some View {
        Button(L10n.text("pinWorkspace.rename")) {
            pinWorkspacePendingRename = workspace
            pinWorkspaceRenameText = workspace.name
        }
        Button(L10n.text("pinWorkspace.duplicate")) {
            pinWorkspacePendingDuplicate = workspace
            pinWorkspaceDuplicateText = ""
        }
        Divider()
        Button(L10n.text("pinWorkspace.exportImages")) { exportPinWorkspace(workspace, format: .images) }
        Button(L10n.text("pinWorkspace.exportPDF")) { exportPinWorkspace(workspace, format: .pdf) }
        Button(L10n.text("pinWorkspace.exportMarkdown")) { exportPinWorkspace(workspace, format: .markdown) }
        Divider()
        Button(L10n.text("pinWorkspace.delete"), role: .destructive) { pinWorkspacePendingDeletion = workspace }
    }

    private func savePinWorkspace() {
        do {
            let workspace = try onSavePinWorkspace(pinWorkspaceName)
            pinWorkspaceName = ""
            selectedWorkspaceID = workspace.id
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
        return historyStore.items.filter { item in
            (!historyKeptOnly || item.isKept) && (query.isEmpty || HistorySearchMatcher.matches(
                item,
                query: query,
                displayName: historyApplicationName(for: item.sourceApplicationBundleIdentifier)
            ))
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
                }.clickCursor()
            }
            Text(L10n.text("history.dimension", item.pixelWidth, item.pixelHeight))
                .font(.system(size: 10))
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
                    .font(.system(size: 11))
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

    private func setHistoryItemKept(_ item: HistoryItem, kept: Bool) {
        do {
            try historyStore.setKept(kept, for: item.id)
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = L10n.text("history.keepFailed", error.localizedDescription)
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
                .font(.system(size: 16, weight: .semibold))
            TextField(L10n.text("pinWorkspace.namePlaceholder"), text: $pinWorkspaceRenameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    renamePinWorkspace(workspace)
                }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    pinWorkspacePendingRename = nil
                }.clickCursor()
                Button(L10n.text("common.save")) {
                    renamePinWorkspace(workspace)
                }.clickCursor()
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
                .font(.system(size: 16, weight: .semibold))
            Text(L10n.text("pinWorkspace.duplicateHelp", workspace.name))
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField(L10n.text("pinWorkspace.duplicatePlaceholder"), text: $pinWorkspaceDuplicateText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    duplicatePinWorkspace(workspace)
                }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    pinWorkspacePendingDuplicate = nil
                }.clickCursor()
                Button(L10n.text("common.save")) {
                    duplicatePinWorkspace(workspace)
                }.clickCursor()
            }
        }
        .padding(22)
        .frame(width: 450, height: 210)
    }

    private var selectedOCRPlugin: OCRPluginManifest? {
        ocrPlugins.first { $0.id == ocrProviderID }
    }

    private var ocrTab: some View {
        VStack(spacing: 0) {
            PreferencesPanePicker(selection: $ocrPane, titles: [
                L10n.text("ocr.preferences.providerSection"), L10n.text("ocr.preferences.pluginsSection")])
            PreferencesPage {
                if ocrPane == 0 {
                    PreferencesGroup(L10n.text("ocr.preferences.providerSection")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 12) {
                            ocrProviderTile(id: OCRPluginConstants.localProviderID,
                                title: L10n.text("ocr.preferences.localProvider"), symbol: "desktopcomputer")
                            ForEach(ocrPlugins) { plugin in
                                ocrProviderTile(id: plugin.id, title: plugin.name, symbol: "network")
                            }
                        }
                        Text(L10n.text(ocrProviderID == OCRPluginConstants.localProviderID
                            ? "ocr.preferences.localHelp" : "ocr.preferences.remoteHelp"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if ocrProviderID == OCRPluginConstants.localProviderID {
                            Button(L10n.text("common.save"), action: saveOCRConfiguration).buttonStyle(.borderedProminent)
                        }
                    }
            if ocrProviderID != OCRPluginConstants.localProviderID {
                PreferencesGroup(L10n.text("ocr.preferences.connectionSection")) {
                    if selectedOCRPlugin == nil {
                        Text(L10n.text("ocr.preferences.pluginUnavailable"))
                            .foregroundStyle(.red)
                    }
                    LabeledContent(L10n.text("ocr.preferences.baseURL")) {
                        TextField("", text: $ocrBaseURL).textContentType(.URL)
                            .accessibilityLabel(L10n.text("ocr.preferences.baseURL"))
                    }
                        LabeledContent(L10n.text("ocr.preferences.model")) {
                        TextField("", text: $ocrModel)
                            .accessibilityLabel(L10n.text("ocr.preferences.model"))
                    }
                    LabeledContent(L10n.text("ocr.preferences.apiKey")) {
                    SecureField(
                        ocrHasSavedAPIKey
                            ? L10n.text("ocr.preferences.apiKeySavedPlaceholder")
                            : L10n.text("ocr.preferences.apiKey"),
                        text: $ocrAPIKey
                    )
                    }
                    Text(L10n.text("ocr.preferences.keychainHelp"))
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(L10n.text("common.save"), action: saveOCRConfiguration).clickCursor()
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedOCRPlugin == nil)
                        if ocrHasSavedAPIKey {
                            Button(L10n.text("ocr.preferences.removeAPIKey"), role: .destructive) {
                                removeOCRAPIKey()
                            }.clickCursor()
                        }
                    }
                }
            }


                } else {
            PreferencesGroup(L10n.text("ocr.preferences.pluginsSection")) {
                HStack {
                    Button(L10n.text("ocr.preferences.openPluginsFolder"), action: openOCRPluginsFolder)
                        .clickCursor()
                    Button(L10n.text("ocr.preferences.reloadPlugins"), action: reloadOCRPlugins).clickCursor()
                }
                Text(L10n.text("ocr.preferences.pluginsHelp"))
                    .foregroundStyle(.secondary)
                if !ocrPluginLoadErrors.isEmpty {
                    Text(L10n.text("ocr.preferences.loadErrors", ocrPluginLoadErrors.count))
                        .foregroundStyle(.orange)
                        .help(ocrPluginLoadErrors.joined(separator: "\n"))
                }
            }


                }
                if let ocrStatusMessage {
                    Text(ocrStatusMessage).foregroundStyle(ocrStatusIsError ? .red : .secondary)
                }
            }
        }
        .onChange(of: ocrProviderID) { _, _ in loadSelectedOCRPluginConfiguration() }
        .onAppear { reloadOCRPlugins(); loadSelectedOCRPluginConfiguration() }
    }

    private func ocrProviderTile(id: String, title: String, symbol: String) -> some View {
        Button { ocrProviderID = id } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: ocrProviderID == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ocrProviderID == id ? Color.primary : Color.secondary.opacity(0.5))
            }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(ocrProviderID == id ? Color.primary.opacity(0.035) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                    ocrProviderID == id ? Color.primary.opacity(0.5) : Color.primary.opacity(0.12)))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(ocrProviderID == id ? [.isSelected] : [])
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
        VStack(spacing: 0) {
            PreferencesPanePicker(
                selection: $generalPane,
                titles: [
                    L10n.text("settings.general.basic"), L10n.text("preferences.capture"),
                    L10n.text("settings.general.connections"), L10n.text("settings.general.advanced"),
                ])
            PreferencesPage {
                if generalPane == 0 {
                    PreferencesGroup(L10n.text("settings.general.basic")) {
                        HStack {
                            Text(L10n.text("preferences.appearance.mode"))
                            Spacer(minLength: 12)
                            Picker(L10n.text("preferences.appearance.mode"), selection: $appAppearance) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                            .onChange(of: appAppearance) { _, appearance in appearance.apply() }
                        }
                        .frame(minHeight: 36)
                        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
                        Text(L10n.text("preferences.appearance.help"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)

                        HStack {
                            Text(L10n.text("preferences.language"))
                            Spacer(minLength: 12)
                        Picker(L10n.text("preferences.language"), selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.title).tag(language)
                            }
                        }.clickCursor()
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }.frame(minHeight: 36)
                            .overlay(alignment: .bottom) { Divider().opacity(0.45) }

                        Toggle(
                            L10n.text("preferences.launchAtLogin"),
                            isOn: Binding(
                                get: { launchAtLoginManager.isEnabled },
                                set: { launchAtLoginManager.setEnabled($0) }
                            )
                        ).clickCursor()
                        if launchAtLoginManager.state == .requiresApproval {
                            Button(L10n.text("preferences.openLoginSettings")) {
                                launchAtLoginManager.openSystemSettings()
                            }.clickCursor()
                        }
                        if let message = launchAtLoginManager.message {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                }
                if generalPane == 0 {
                    PreferencesGroup(L10n.text("preferences.menuDisplay")) {
                        TrayMenuDisplayPreferences()
                        Text(L10n.text("preferences.menuDisplayHelp"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if generalPane == 2 {
                    PreferencesGroup(L10n.text("browserExtension.title")) {
                        TimelineView(.periodic(from: .now, by: 3)) { context in
                            let connected =
                                (try? BrowserExtensionPresenceStore().connectedExtensionIDs(now: context.date))
                                ?? []
                            Text(
                                L10n.text(
                                    connected.isEmpty ? "browserExtension.notDetected" : "browserExtension.connected")
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                        }
                        Text(L10n.text("browserExtension.help"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(
                                L10n.text("browserExtension.downloadLocal"), action: onDownloadBrowserExtension
                            ).clickCursor()
                            Link(
                                L10n.text("browserExtension.installFromStore"),
                                destination: BrowserExtensionSetup.storeURL
                            ).clickCursor()
                        }
                        Text(L10n.text("browserExtension.localHelp"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Button(L10n.text("browserExtension.prepare"), action: onPrepareBrowserExtension)
                            .clickCursor()
                        Button(L10n.text("browserExtension.start"), action: onStartBrowserCapture).clickCursor()
                        Text(L10n.text("browserExtension.startHelp"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                if generalPane == 2 {
                    PreferencesGroup(L10n.text("preferences.screenCapturePermission")) {
                        HStack {
                            Label(
                                L10n.text(
                                    appHealth.screenCapturePermissionGranted
                                        ? "preferences.permissionGranted" : "preferences.permissionMissing"),
                                systemImage: appHealth.screenCapturePermissionGranted
                                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(appHealth.screenCapturePermissionGranted ? Color.secondary : Color.orange)
                            Spacer()
                            if !appHealth.screenCapturePermissionGranted {
                                Button(
                                    L10n.text("onboarding.requestPermission"),
                                    action: onRequestScreenCapturePermission
                                ).clickCursor()
                            }
                            Button(L10n.text("permission.openSettings"), action: onOpenScreenCaptureSettings)
                                .clickCursor()
                        }
                        Text(L10n.text("preferences.permissionHelp"))
                            .foregroundStyle(.secondary)
                        Button(L10n.text("preferences.copyDiagnostics")) {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(CaptureDiagnostics.report(), forType: .string)
                        }.clickCursor()
                        Text(L10n.text("preferences.diagnosticsHelp"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if generalPane == 0 {
                    PreferencesGroup(L10n.text("preferences.trayIcon")) {
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
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if generalPane == 1 {
                    PreferencesGroup(L10n.text("preferences.capture")) {
                        HStack {
                            Text(L10n.text("preferences.outputQuality"))
                            Spacer(minLength: 12)
                        Picker(L10n.text("preferences.outputQuality"), selection: captureQualityBinding) {
                            ForEach(CaptureQuality.allCases) { quality in
                                Text(quality.title).tag(quality)
                            }
                        }.clickCursor()
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }.frame(minHeight: 36)
                            .overlay(alignment: .bottom) { Divider().opacity(0.45) }
                        Toggle(L10n.text("preferences.includeCursor"), isOn: $captureCursor).clickCursor()
                        Toggle(
                            L10n.text("preferences.captureSelectionAlwaysOnTop"),
                            isOn: $captureSelectionAlwaysOnTop
                        ).clickCursor()
                        Text(L10n.text("preferences.captureSelectionAlwaysOnTopHelp"))
                            .foregroundStyle(.secondary)
                        Toggle(L10n.text("preferences.captureAnimation"), isOn: $captureEntranceAnimation)
                            .clickCursor()
                        Toggle(L10n.text("preferences.quickCaptureOverlay"), isOn: $quickCaptureOverlayEnabled)
                            .clickCursor()
                        Text(L10n.text("preferences.quickCaptureOverlayHelp"))
                            .foregroundStyle(.secondary)
                        Toggle(L10n.text("preferences.allowDarkCaptures"), isOn: $allowUniformDarkCaptures)
                            .clickCursor()
                        Text(L10n.text("preferences.allowDarkCapturesHelp"))
                            .foregroundStyle(.secondary)
                        Text(L10n.text("preferences.qualityHelp"))
                            .foregroundStyle(.secondary)
                        if selectedCaptureQuality == .uhd8K {
                            Text(L10n.text("preferences.8kWarning"))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if generalPane == 3 {
                    PreferencesGroup(L10n.text("preferences.updates")) {
                        Toggle(
                            L10n.text("preferences.automaticallyCheckForUpdates"),
                            isOn: automaticUpdateChecksBinding
                        ).clickCursor()
                        HStack {
                            Text(L10n.text("preferences.updateCheckFrequency"))
                            Spacer(minLength: 12)
                        Picker(
                            L10n.text("preferences.updateCheckFrequency"),
                            selection: updateCheckFrequencyBinding
                        ) {
                            ForEach(UpdateCheckFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }.clickCursor()
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                            .disabled(!updateManager.automaticallyChecksForUpdates)
                        }.frame(minHeight: 36)
                            .overlay(alignment: .bottom) { Divider().opacity(0.45) }
                        Text(L10n.text("preferences.updateCheckHelp"))
                            .foregroundStyle(.secondary)
                    }
                }
                if generalPane == 3 {
                    PreferencesGroup(L10n.text("preferences.privacy")) {
                        Toggle(L10n.text("preferences.clearOnQuit"), isOn: $clearHistoryOnQuit).clickCursor()
                        Text(L10n.text("preferences.localOnly"))
                            .foregroundStyle(.secondary)
                    }
                }
                if generalPane == 1 {
                    PreferencesGroup(L10n.text("preferences.pinOperations")) {
                        Toggle(L10n.text("preferences.pinShadow"), isOn: $pinWindowShadow).clickCursor()
                            .onChange(of: pinWindowShadow) { _, enabled in onPinShadowChanged(enabled) }
                        Text(L10n.text("preferences.pinHelp"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            launchAtLoginManager.refresh()
            updateManager.refreshSettings()
        }
    }

    private var toolbarTab: some View {
        VStack(spacing: 0) {
            PreferencesPanePicker(
                selection: $toolbarPane,
                titles: [
                    L10n.text("settings.toolbar.arrange"), L10n.text("preferences.selectionToolbarIcons"),
                ])
            PreferencesPage {
                if toolbarPane == 0 {
                    PreferencesGroup(L10n.text("settings.toolbar.preview")) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                ForEach(
                                    toolbarConfiguredActionOrder.filter {
                                        toolbarRequiredActions.contains($0)
                                            || toolbarVisibleActions[$0.rawValue] == true
                                    }, id: \.rawValue
                                ) { action in
                                    Image(systemName: action.symbolName())
                                        .font(.system(size: 15)).frame(width: 32, height: 32)
                                        .help(L10n.text(action.titleKey))
                                        .accessibilityLabel(L10n.text(action.titleKey))
                                }
                            }
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
                            .padding(16)
                        }.background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                if toolbarPane == 0 {
                    PreferencesGroup(L10n.text("preferences.selectionToolbar.configuration")) {
                        ForEach(Array(toolbarConfiguredActionOrder.enumerated()), id: \.element.rawValue) {
                            index, action in
                            HStack(spacing: 10) {
                                Image(systemName: action.symbolName())
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 24, height: 24)

                                Text(L10n.text(action.titleKey))
                                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

                                if toolbarRequiredActions.contains(action) {
                                    Text(L10n.text("preferences.selectionToolbar.required"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle(
                                    "",
                                    isOn: toolbarVisibilityBinding(for: action)
                                ).clickCursor()
                                    .labelsHidden().toggleStyle(.switch).fixedSize()
                                    .accessibilityLabel(L10n.text(action.titleKey))
                                    .disabled(toolbarRequiredActions.contains(action))

                                Button {
                                    moveToolbarAction(action, direction: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }.clickCursor()
                                    .buttonStyle(.plain)
                                    .disabled(index == 0)
                                    .help(L10n.text("preferences.selectionToolbar.moveUp"))
                                    .accessibilityLabel(L10n.text("preferences.selectionToolbar.moveUp"))

                                Button {
                                    moveToolbarAction(action, direction: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }.clickCursor()
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
                                    SelectionToolbarConfiguration.setAutomaticallySortsByUsage(
                                        enabled, defaults: UserDefaults.standard)
                                }
                            )
                        ).clickCursor()
                        Text(L10n.text("preferences.selectionToolbar.autoSortHelp"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(L10n.text("preferences.selectionToolbar.visibilityHelp"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                if toolbarPane == 1 {
                    PreferencesGroup(L10n.text("preferences.selectionToolbarIcons")) {
                        ForEach(SelectionToolbarAction.allCases.filter { $0 != .annotate }, id: \.rawValue) {
                            action in
                            SelectionToolbarIconField(action: action)
                        }
                        Text(L10n.text("preferences.selectionToolbarIconsHelp"))
                            .foregroundStyle(.secondary)
                    }
                }

                Button(L10n.text("preferences.selectionToolbar.reset")) {
                    resetToolbarConfiguration()
                }.clickCursor()
                    .padding(.top, 6)
            }
        }
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
        PreferencesPage {
            PreferencesGroup(L10n.text("watermark.preferences.section")) {
                Toggle(L10n.text("watermark.preferences.enabled"), isOn: $invisibleWatermarkEnabled)
                    .clickCursor()
                Text(L10n.text("watermark.preferences.enabledHelp"))
                    .foregroundStyle(.secondary)
            }
            PreferencesGroup(L10n.text("watermark.preferences.details")) {
                LabeledContent(L10n.text("watermark.preferences.project")) {
                        TextField("", text: $watermarkProject)
                            .accessibilityLabel(L10n.text("watermark.preferences.project"))
                    }
                    .disabled(!invisibleWatermarkEnabled)
                LabeledContent(L10n.text("watermark.preferences.recipient")) {
                        TextField("", text: $watermarkRecipient)
                            .accessibilityLabel(L10n.text("watermark.preferences.recipient"))
                    }
                    .disabled(!invisibleWatermarkEnabled)
                LabeledContent(L10n.text("watermark.preferences.customText")) {
                TextField(
                    "", text: $watermarkCustomText, axis: .vertical
                )
                .lineLimit(2...4)
                .disabled(!invisibleWatermarkEnabled)
                }
                Text(L10n.text("watermark.preferences.privacyPreview"))
                    .foregroundStyle(.secondary)
            }
            PreferencesGroup(L10n.text("watermark.preferences.localRecords")) {
                Text(L10n.text("watermark.preferences.recordCount", watermarkStore.records.count))
                Button(L10n.text("watermark.preferences.clearRecords"), role: .destructive) {
                    isConfirmingWatermarkClear = true
                }.clickCursor()
                    .disabled(watermarkStore.records.isEmpty)
                if let watermarkErrorMessage {
                    Text(watermarkErrorMessage).foregroundStyle(.red)
                }
            }
        }
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
                    watermarkErrorMessage = L10n.text(
                        "watermark.preferences.clearFailed", error.localizedDescription)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 68), spacing: 8)], spacing: 8) {
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
        let displayedIconColor: Color = iconColor
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
                        .fill(isSelected ? Color.primary.opacity(0.06) : Color.secondary.opacity(0.07))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.primary.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        ZStack {
                            Circle().fill(Color(nsColor: .labelColor))
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                        }
                        .frame(width: 14, height: 14)
                        .offset(x: 4, y: -4)
                    }
                }
                .shadow(
                    color: .clear,
                    radius: 3,
                    y: 1
                )
        }.clickCursor()
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

private struct PreferencesRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden().toggleStyle(.switch).fixedSize()
        }
        .frame(minHeight: 36)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }
}

private struct PreferencesFieldStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            configuration.label.frame(width: 132, alignment: .leading).foregroundStyle(.secondary)
            configuration.content.frame(maxWidth: 320)
            Spacer(minLength: 0)
        }.frame(minHeight: 34)
    }
}

private struct PreferencesPage<Content: View>: View {
    var maximumWidth: CGFloat = 720
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: maximumWidth, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        }
        .textFieldStyle(.roundedBorder)
    }
}

private struct PreferencesGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String?
    var spacing: CGFloat
    @ViewBuilder var content: Content
    init(_ title: String? = nil, spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.title = title
        self.spacing = spacing
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(colorScheme == .dark ? Color(white: 0.16) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 5, y: 2)
        }
    }
}

private struct PreferencesPanePicker: View {
    @Binding var selection: Int
    let titles: [String]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(titles.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Text(titles[index]).font(.system(size: 12, weight: selection == index ? .medium : .regular))
                        .foregroundStyle(selection == index ? Color.primary : Color.secondary)
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            if selection == index { Rectangle().fill(Color.primary.opacity(0.7)).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == index ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Divider() }
        .padding(.horizontal, 28)
        .frame(maxWidth: 776, alignment: .leading)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("settings.pageNavigation"))
    }
}

private struct PreferencesSearchField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 10))
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 11))
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.text("settings.search.clear"))
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12)))
    }
}

private struct PreferencesEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 24)
    }
}

private struct HistoryThumbnailView: View {
    @ObservedObject var historyStore: HistoryStore
    let item: HistoryItem
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04))
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 59, height: 42).clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.09)))
        .task(id: item.id) {
            thumbnail = nil
            thumbnail = await historyStore.thumbnail(for: item)
        }
    }
}

private struct HistoryPreviewImage: View {
    @ObservedObject var historyStore: HistoryStore
    let item: HistoryItem
    @State private var preview: NSImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let preview {
                Image(nsImage: preview).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .accessibilityLabel(L10n.text("history.dimension", item.pixelWidth, item.pixelHeight))
            } else if loaded {
                Text(L10n.text("history.imageMissing")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            preview = nil
            loaded = false
            let image = await historyStore.thumbnail(for: item, maxPixelSize: 2400)
            guard !Task.isCancelled else { return }
            preview = image
            loaded = true
        }
    }
}

private struct PreferencesWorkspacePreview: View {
    let store: PinWorkspaceStore
    let workspace: PinWorkspaceSummary
    @State private var result: PinWorkspaceLoadResult?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                GeometryReader { geometry in
                    let bounds = result.entries.map(\.state.frame).reduce(CGRect.null) { $0.union($1) }
                    let scale = min(geometry.size.width / max(bounds.width, 1), geometry.size.height / max(bounds.height, 1))
                    let origin = CGPoint(x: (geometry.size.width - bounds.width * scale) / 2,
                                         y: (geometry.size.height - bounds.height * scale) / 2)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(result.entries.enumerated()), id: \.offset) { _, entry in
                            Image(nsImage: entry.image).resizable().scaledToFit()
                                .frame(width: entry.state.frame.width * scale, height: entry.state.frame.height * scale)
                                .background(Color(nsColor: .textBackgroundColor))
                                .opacity(entry.state.opacity)
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                .position(x: origin.x + (entry.state.frame.midX - bounds.minX) * scale,
                                          y: origin.y + (bounds.maxY - entry.state.frame.midY) * scale)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                if result.skippedPinCount > 0 {
                    Text(L10n.text("settings.workspace.skipped", result.skippedPinCount))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !workspace.aggregateTags.isEmpty {
                    Text(workspace.aggregateTags.joined(separator: " · "))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                if !workspace.searchableNotes.isEmpty {
                    Text(workspace.searchableNotes.joined(separator: "\n"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                }
            } else if let message {
                Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: workspace) {
            result = nil
            message = nil
            do { result = try store.load(workspace) }
            catch { message = error.localizedDescription }
        }
    }
}

private struct PreferencesStorageBar: View {
    struct Segment {
        let title: String
        let bytes: Int64
        let shade: Double
    }
    let segments: [Segment]
    private var total: Int64 { segments.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments.indices, id: \.self) { index in
                        if segments[index].bytes > 0 {
                            Rectangle().fill(Color.primary.opacity(segments[index].shade))
                                .frame(width: max(0, geometry.size.width - CGFloat(segments.filter { $0.bytes > 0 }.count - 1) * 2)
                                    * CGFloat(segments[index].bytes) / CGFloat(max(total, 1)))
                        }
                    }
                }
            }.frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 3))
                .background(Color.primary.opacity(0.04))
                .accessibilityHidden(true)
            ForEach(segments.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Circle().fill(Color.primary.opacity(segments[index].shade)).frame(width: 6, height: 6)
                    Text(segments[index].title)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: segments[index].bytes, countStyle: .file))
                        .monospacedDigit().foregroundStyle(.secondary)
                }.font(.system(size: 11))
            }
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
                                    .fill(
                                        candidate == selectedSymbolName
                                            ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(
                                        candidate == selectedSymbolName
                                            ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                    }.clickCursor()
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
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: section.systemImage).font(.system(size: 16, weight: .regular))
                    .frame(width: 22, height: 20)
                Text(section.railTitle).font(.system(size: 9)).lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color(nsColor: .textBackgroundColor) : Color.secondary)
            .frame(width: 42, height: 46)
            .background {
                RoundedRectangle(cornerRadius: 6).fill(
                    isSelected ? Color(nsColor: .labelColor) : Color.primary.opacity(isHovering ? 0.05 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }.clickCursor().buttonStyle(.plain)
            .help(section.title).accessibilityLabel(section.title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .onHover { isHovering = $0 }
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("preferences.addShortcut")).font(.system(size: 16, weight: .semibold))

            Picker(L10n.text("preferences.triggerAction"), selection: $selectedAction) {
                ForEach(CaptureAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }.clickCursor()

            HStack {
                Text(L10n.text("preferences.keyCombination"))
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut) { shortcut = $0 }
                    .frame(width: 140, height: 28)
            }

            Text(L10n.text("preferences.recordHelp"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) { dismiss() }.clickCursor()
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("common.add")) {
                    if onAdd(selectedAction, shortcut) {
                        dismiss()
                    } else {
                        errorMessage = L10n.text("preferences.shortcutConflict")
                    }
                }.clickCursor()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 12)).controlSize(.small)
    }
}

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSButton {
        let button = ActionButton(
            title: shortcut.displayText, target: context.coordinator,
            action: #selector(Coordinator.beginRecording(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
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
