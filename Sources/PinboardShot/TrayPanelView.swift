import SwiftUI

enum TrayPanelMetrics {
    static let width: CGFloat = 340
    static let fallbackHeight: CGFloat = 628
    static let measurementHeightLimit: CGFloat = 10_000
    static let screenVerticalMargin: CGFloat = 24
    static let pinboardPreviewHeight: CGFloat = 124

    static func height(preferredHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(
            ceil(max(0, preferredHeight)),
            max(0, availableHeight - screenVerticalMargin)
        )
    }
}

enum OrbitalPalette {
    static let backgroundTop = Color(red: 0.996, green: 0.998, blue: 1.000)
    static let backgroundBottom = Color(red: 0.958, green: 0.972, blue: 0.992)
    static let blue = Color(red: 0.04, green: 0.39, blue: 0.96)
    static let cyan = Color(red: 0.00, green: 0.62, blue: 0.70)
    static let green = Color(red: 0.09, green: 0.74, blue: 0.28)
    static let red = Color(red: 1.00, green: 0.19, blue: 0.12)
    static let text = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let secondaryText = Color(red: 0.39, green: 0.43, blue: 0.51)
    static let nodeFill = Color(red: 0.974, green: 0.982, blue: 0.994)
    static let nodeEdge = Color(red: 0.73, green: 0.77, blue: 0.84)
}

private enum TrayPanelTone {
    case primary
    case pin
    case utility
    case success
    case neutral
    case warning
    case danger

    var color: Color {
        switch self {
        case .primary: OrbitalPalette.blue
        case .pin: Color(nsColor: .systemPurple)
        case .utility: OrbitalPalette.cyan
        case .success: OrbitalPalette.green
        case .neutral: OrbitalPalette.nodeEdge
        case .warning: Color(nsColor: .systemOrange)
        case .danger: OrbitalPalette.red
        }
    }
}

private enum TrayPanelIcon {
    case app
    case captureRegion
    case captureDelayedRegion
    case captureRepeatRegion
    case filePin
    case captureScrollingRegion
    case captureDisplay
    case captureWindow
    case captureRegionAndPin
    case clipboardPin
    case showPins
    case hidePins
    case restorePinInteraction
    case closePins
    case shortcuts
    case history
    case watermarkSettings
    case toolbarSettings
    case generalSettings
    case detectWatermark
    case quickStart
    case letterToUsers
    case legalNotices
    case checkForUpdates
    case about
    case includeCursor
    case captureAnimation
    case pinShadow
    case magneticDesktop
    case permissionWarning
    case hotKeyError
    case updateAvailable
    case quit

    var systemName: String {
        switch self {
        case .app: "viewfinder.rectangular"
        case .captureRegion: "crop"
        case .captureDelayedRegion: "timer"
        case .captureRepeatRegion: "repeat"
        case .filePin: "photo.badge.plus"
        case .captureScrollingRegion: "rectangle.stack"
        case .captureDisplay: "display"
        case .captureWindow: "macwindow"
        case .captureRegionAndPin: "pin"
        case .clipboardPin: "doc.on.clipboard"
        case .showPins: "eye"
        case .hidePins: "eye.slash"
        case .restorePinInteraction: "cursorarrow.rays"
        case .closePins: "xmark.circle"
        case .shortcuts: "keyboard"
        case .history: "clock"
        case .watermarkSettings: "eye.slash"
        case .toolbarSettings: "slider.horizontal.2.square"
        case .generalSettings: "slider.horizontal.3"
        case .detectWatermark: "doc.text.magnifyingglass"
        case .quickStart: "book.closed"
        case .letterToUsers: "text.bubble"
        case .legalNotices: "doc.plaintext"
        case .checkForUpdates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        case .includeCursor: "cursorarrow"
        case .captureAnimation: "play.rectangle"
        case .pinShadow: "shadow"
        case .magneticDesktop: "rectangle.stack"
        case .permissionWarning: "exclamationmark.triangle.fill"
        case .hotKeyError: "exclamationmark.circle.fill"
        case .updateAvailable: "sparkles"
        case .quit: "power"
        }
    }

    var tone: TrayPanelTone {
        switch self {
        case .app, .captureRegion, .captureDelayedRegion, .captureRepeatRegion, .filePin, .captureScrollingRegion, .captureDisplay, .captureWindow, .captureRegionAndPin,
             .clipboardPin, .captureAnimation, .pinShadow:
            .primary
        case .showPins, .hidePins, .restorePinInteraction, .magneticDesktop:
            .pin
        case .detectWatermark, .quickStart, .letterToUsers, .legalNotices:
            .utility
        case .checkForUpdates:
            .success
        case .permissionWarning:
            .warning
        case .updateAvailable:
            .success
        case .hotKeyError, .closePins, .quit:
            .danger
        case .shortcuts, .history, .watermarkSettings, .toolbarSettings, .generalSettings, .about, .includeCursor:
            .neutral
        }
    }
}

enum TrayPanelCommand {
    case showCaptureTools
    case startBrowserCapture
    case capture(CaptureAction)
    case closeAllPins
    case restorePinInteraction
    case detectWatermark
    case requestScreenRecordingPermission
    case showHotKeyFailures
    case showPreferences(PreferencesSection)
    case showQuickStart
    case showLetterToUsers
    case showLegalNotices
    case showAbout
    case checkForUpdates
    case quit
}

struct TrayPanelView: View {
    let permissionGranted: Bool
    let failedHotKeyCount: Int
    let canCheckForUpdates: Bool
    let lastUpdateCheckDate: Date?
    let updateNotice: UpdateNotice?
    let pinCount: Int
    let pinsAreVisible: Bool
    let height: CGFloat?
    let onPinShadowChanged: (Bool) -> Void
    let onDismissUpdateNotice: () -> Void
    let onCommand: (TrayPanelCommand) -> Void
    var onContentHeightChanged: ((CGFloat) -> Void)? = nil
    var maximumHeight: CGFloat? = nil

    @AppStorage(CaptureQuality.userDefaultsKey)
    private var captureQualityRawValue = CaptureQuality.defaultValue.rawValue
    @AppStorage("captureCursor") private var captureCursor = false
    @AppStorage(OverlaySafetyPolicy.animationDefaultsKey) private var captureEntranceAnimation = true
    @AppStorage(PinWindowManager.shadowDefaultsKey) private var pinWindowShadow = true
    @AppStorage(TrayMenuConfigurationItem.outputQuality.visibilityKey) private var showsOutputQuality = true
    @AppStorage(TrayMenuConfigurationItem.includeCursor.visibilityKey) private var showsIncludeCursor = true
    @AppStorage(TrayMenuConfigurationItem.captureAnimation.visibilityKey) private var showsCaptureAnimation = true
    @AppStorage(TrayMenuConfigurationItem.pinShadow.visibilityKey) private var showsPinShadow = true
    @AppStorage(TrayMenuConfigurationItem.magneticDesktop.visibilityKey) private var showsMagneticDesktop = true
    @AppStorage(MagneticDesktopSettings.enabledKey) private var magneticDesktopEnabled = false
    @AppStorage(MagneticDesktopSettings.maximumVisibleKey)
    private var magneticMaximumVisible = MagneticDesktopSettings.defaultMaximumVisible
    @AppStorage(HistorySettings.enabledDefaultsKey) private var historyEnabled = true
    @State private var isMoreExpanded = false
    @State private var isQuickSettingsExpanded = true
    @State private var preferredContentHeight: CGFloat?

    private var showsQuickSettings: Bool {
        showsIncludeCursor || showsCaptureAnimation || showsPinShadow || showsMagneticDesktop
    }

    private var appVersionLabel: String? {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        !version.isEmpty else {
            return nil
        }
        return "v\(version)"
    }

    var body: some View {
        Group {
            if let height {
                ZStack(alignment: .topLeading) {
                    TrayPanelBackdrop()
                    mainPage
                }
                .frame(width: TrayPanelMetrics.width, height: min(preferredContentHeight ?? height, maximumHeight ?? height))
                .onPreferenceChange(TrayPanelContentHeightKey.self) { measurements in
                    guard let header = measurements["header"], let content = measurements["content"] else { return }
                    let preferredHeight = ceil(header + content + 6 + 10 + 8)
                    guard preferredHeight.isFinite, preferredHeight > 0 else { return }
                    // Measure the scroll content itself so hidden rows also release native window space.
                    preferredContentHeight = preferredHeight
                    onContentHeightChanged?(min(preferredHeight, maximumHeight ?? height))
                }
            } else {
                panelPage(scrolls: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: TrayPanelMetrics.width)
                    .background(TrayPanelBackdrop())
            }
        }
        .background(.clear)
        .onChange(of: pinWindowShadow) { _, enabled in
            onPinShadowChanged(enabled)
        }
    }

    private var mainPage: some View {
        panelPage(scrolls: true)
    }

    private func panelPage(scrolls: Bool) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 6) {
                header
                statusNotices
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: TrayPanelContentHeightKey.self, value: ["header": geometry.size.height])
                }
            }

            if scrolls {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        panelContent
                            .padding(.bottom, 8)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: TrayPanelContentHeightKey.self, value: ["content": geometry.size.height])
                                }
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .onChange(of: isMoreExpanded) { _, expanded in
                        if expanded {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                scrollProxy.scrollTo("more", anchor: .center)
                            }
                        }
                    }
                }
            } else {
                panelContent
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var panelContent: some View {
        VStack(spacing: 7) {
            if showsOutputQuality { qualityHero }
            pinboardPreview
            if pinCount > 0 {
                pinActionsOrbit
            }
            managementToolsOrbit
            appInfoOrbit
            quitOrbit
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [OrbitalPalette.blue, Color(red: 0.05, green: 0.31, blue: 0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: OrbitalPalette.blue.opacity(0.20), radius: 10, y: 4)

                Image(systemName: TrayPanelIcon.app.systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("PinboardShot")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(permissionGranted ? OrbitalPalette.green : Color.orange)
                        .frame(width: 7, height: 7)

                    Text(permissionGranted ? L10n.text("menu.ready") : L10n.text("menu.permissionRequired"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OrbitalPalette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Button {
                onCommand(.showPreferences(.general))
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OrbitalPalette.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(OrbitalPalette.nodeEdge.opacity(0.35), lineWidth: 0.6)
                    )
            }.clickCursor()
            .buttonStyle(.plain)
        }
        .frame(minHeight: 46)
    }

    @ViewBuilder
    private var statusNotices: some View {
        if let updateNotice {
            TrayUpdateNotice(
                notice: updateNotice,
                installAction: { onCommand(.checkForUpdates) },
                dismissAction: onDismissUpdateNotice
            )
        }
        if !permissionGranted {
            TrayNoticeRow(
                title: L10n.text("menu.permissionMissing"),
                icon: .permissionWarning,
                action: { onCommand(.requestScreenRecordingPermission) }
            )
        }
        if failedHotKeyCount > 0 {
            TrayNoticeRow(
                title: L10n.text("menu.hotkeyFailures", failedHotKeyCount),
                icon: .hotKeyError,
                action: { onCommand(.showHotKeyFailures) }
            )
        }
    }

    private var qualityHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OrbitalPalette.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(OrbitalPalette.nodeEdge.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

                Text(L10n.text("preferences.outputQuality"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrbitalPalette.secondaryText)

                Spacer(minLength: 0)

                Text(selectedCaptureQuality.title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OrbitalPalette.text)
                    .contentTransition(.numericText())
            }

            QualityRulerControl(selection: captureQualityBinding)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.34), lineWidth: 0.6)
        )
    }

    private var captureOrbit: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            TrayCommandTile(
                title: CaptureAction.region.title,
                icon: .captureRegion,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.region)) }
            )

            TrayCommandTile(
                title: CaptureAction.delayedRegion.title,
                icon: .captureDelayedRegion,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.delayedRegion)) }
            )

            TrayCommandTile(
                title: CaptureAction.repeatRegion.title,
                icon: .captureRepeatRegion,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.repeatRegion)) }
            )

            TrayCommandTile(
                title: CaptureAction.filePin.title,
                icon: .filePin,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.filePin)) }
            )

            TrayCommandTile(
                title: CaptureAction.scrollingRegion.title,
                icon: .captureScrollingRegion,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.scrollingRegion)) }
            )

            TrayCommandTile(
                title: L10n.text("browserExtension.title"),
                icon: .captureScrollingRegion,
                tone: .primary,
                style: .large,
                action: { onCommand(.startBrowserCapture) }
            )

            TrayCommandTile(
                title: CaptureAction.regionAndPin.title,
                icon: .captureRegionAndPin,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.regionAndPin)) }
            )

            TrayCommandTile(
                title: CaptureAction.display.title,
                icon: .captureDisplay,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.display)) }
            )

            TrayCommandTile(
                title: CaptureAction.window.title,
                icon: .captureWindow,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.window)) }
            )

            TrayCommandTile(
                title: CaptureAction.clipboardPin.title,
                icon: .clipboardPin,
                tone: .primary,
                style: .large,
                action: { onCommand(.capture(.clipboardPin)) }
            )
        }
        .padding(0)
        .padding(4)
        .frame(height: 188)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.38), lineWidth: 0.6)
        )
    }

    private var pinboardPreview: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("tray.pinboard.title"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(L10n.text("tray.pinboard.subtitle"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrbitalPalette.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if pinCount > 0 {
                        onCommand(.capture(.togglePins))
                    } else {
                        onCommand(.showPreferences(.history))
                    }
                } label: {
                    Text(pinCount > 0 ? L10n.text(pinsAreVisible ? "menu.hideAllPins" : "menu.showAllPins") : L10n.text("preferences.history"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OrbitalPalette.blue)
                        .lineLimit(1)
                }.clickCursor()
                .buttonStyle(.plain)
            }
            .frame(width: 104, alignment: .leading)
            .padding(.leading, 15)

            ZStack {
                Image("TrayPanelPinboardPreview")
                    .resizable()
                    .scaledToFill()
            }
            .frame(
                maxWidth: .infinity,
                minHeight: TrayPanelMetrics.pinboardPreviewHeight,
                maxHeight: TrayPanelMetrics.pinboardPreviewHeight
            )
            .clipped()
        }
        .frame(maxWidth: .infinity, minHeight: TrayPanelMetrics.pinboardPreviewHeight)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.34), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var captureSettingsOrbit: some View {
        VStack(spacing: 0) {
            if showsIncludeCursor {
                TrayToggleTile(
                    title: L10n.text("tray.setting.includeCursor"),
                    icon: .includeCursor,
                    isOn: $captureCursor,
                    width: 0,
                    height: 0
                )
            }
            if showsIncludeCursor && showsCaptureAnimation { TrayDivider() }
            if showsCaptureAnimation {
                TrayToggleTile(
                    title: L10n.text("tray.setting.captureAnimation"),
                    icon: .captureAnimation,
                    isOn: $captureEntranceAnimation,
                    width: 0,
                    height: 0
                )
            }
        }
    }

    private var magneticDesktopSettingsOrbit: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrayToggleTile(
                title: L10n.text("magnetic.enabled"),
                icon: .magneticDesktop,
                isOn: $magneticDesktopEnabled,
                width: 0,
                height: 0
            )
            if magneticDesktopEnabled {
                TrayDivider()
                magneticMaximumControl
                if !historyEnabled {
                    Text(L10n.text("magnetic.needsHistory"))
                        .font(.system(size: 11))
                        .foregroundStyle(OrbitalPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var magneticMaximumControl: some View {
        HStack(spacing: 8) {
            Text(L10n.text("magnetic.maximumLabel"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(OrbitalPalette.secondaryText)

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                Button {
                    magneticMaximumVisible -= 1
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }.clickCursor()
                .disabled(magneticMaximumVisible <= MagneticDesktopSettings.supportedLimits.lowerBound)

                Text(L10n.text("magnetic.maximumCount", magneticMaximumVisible))
                    .font(.system(size: 11.3, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 42)

                Button {
                    magneticMaximumVisible += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }.clickCursor()
                .disabled(magneticMaximumVisible >= MagneticDesktopSettings.supportedLimits.upperBound)
            }
            .buttonStyle(.plain)
            .foregroundStyle(OrbitalPalette.text)
            .background(OrbitalPalette.nodeFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(OrbitalPalette.nodeEdge.opacity(0.34), lineWidth: 0.6)
            )
        }
        .frame(height: 34)
        // Keep the subordinate label aligned with the toggle's text, after its icon and gap.
        .padding(.leading, 34)
        .padding(.trailing, 4)
        .opacity(magneticDesktopEnabled ? 1 : 0.45)
        .disabled(!magneticDesktopEnabled)
        .help(L10n.text("magnetic.help"))
        .accessibilityRepresentation {
            Stepper(value: $magneticMaximumVisible, in: MagneticDesktopSettings.supportedLimits) {
                Text(L10n.text("magnetic.maximum", magneticMaximumVisible))
            }
            .disabled(!magneticDesktopEnabled)
        }
    }

    private var pinboardSettingsOrbit: some View {
        TrayToggleTile(
            title: L10n.text("tray.setting.pinShadow"),
            icon: .pinShadow,
            isOn: $pinWindowShadow,
            width: 0,
            height: 0
        )
    }

    private var pinActionsOrbit: some View {
        TrayModuleShell(title: L10n.text("menu.pinsWithCount", pinCount), tone: .pin) {
            HStack(spacing: 8) {
                TrayCommandTile(
                    title: L10n.text(pinsAreVisible ? "menu.hideAllPins" : "menu.showAllPins"),
                    icon: pinsAreVisible ? .hidePins : .showPins,
                    tone: .pin,
                    style: .compact,
                    action: { onCommand(.capture(.togglePins)) }
                )
                TrayCommandTile(
                    title: L10n.text("menu.restorePinInteraction"),
                    icon: .restorePinInteraction,
                    tone: .pin,
                    style: .compact,
                    helpText: L10n.text("menu.restorePinInteractionHelp"),
                    action: { onCommand(.restorePinInteraction) }
                )
                TrayCommandTile(
                    title: L10n.text("menu.closeAllPins"),
                    icon: .closePins,
                    tone: .danger,
                    style: .compact,
                    role: .destructive,
                    action: { onCommand(.closeAllPins) }
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var managementToolsOrbit: some View {
        VStack(spacing: 0) {
            if showsQuickSettings {
                TrayListRow(
                    title: L10n.text("menu.quickSettings"), icon: .toolbarSettings,
                    rowHeight: 38, isExpanded: isQuickSettingsExpanded
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isQuickSettingsExpanded.toggle()
                    }
                }
                if isQuickSettingsExpanded {
                    TrayDivider()
                    if showsIncludeCursor || showsCaptureAnimation { captureSettingsOrbit }
                    if showsPinShadow {
                        if showsIncludeCursor || showsCaptureAnimation { TrayDivider() }
                        pinboardSettingsOrbit
                    }
                    if showsMagneticDesktop {
                        if showsIncludeCursor || showsCaptureAnimation || showsPinShadow { TrayDivider() }
                        magneticDesktopSettingsOrbit
                    }
                }
                TrayDivider()
            }
            TrayListRow(title: PreferencesSection.general.title, icon: .generalSettings, rowHeight: 38) {
                onCommand(.showPreferences(.general))
            }
            TrayDivider()
            moreOrbit.id("more")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.32), lineWidth: 0.6)
        )
    }

    private var moreOrbit: some View {
        VStack(spacing: 0) {
            TrayListRow(title: L10n.text("menu.more"), icon: .detectWatermark, rowHeight: 38, isExpanded: isMoreExpanded) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isMoreExpanded.toggle()
                }
            }

            if isMoreExpanded {
                TrayDivider()
                TrayListRow(title: L10n.text("tray.detectWatermark"), icon: .detectWatermark) {
                    onCommand(.detectWatermark)
                }
                TrayDivider()
                TrayListRow(title: L10n.text("tray.quickStart"), icon: .quickStart) {
                    onCommand(.showQuickStart)
                }
                TrayDivider()
                TrayListRow(title: L10n.text("tray.letterToUsers"), icon: .letterToUsers) {
                    onCommand(.showLetterToUsers)
                }
                TrayDivider()
                TrayListRow(title: L10n.text("tray.legalNotices"), icon: .legalNotices) {
                    onCommand(.showLegalNotices)
                }
            }
        }
    }

    private var appInfoOrbit: some View {
        VStack(spacing: 0) {
            TrayListRow(
                title: L10n.text("tray.checkForUpdates"),
                icon: .checkForUpdates,
                detail: UpdateLastCheckDisplay.menuDetail(for: lastUpdateCheckDate),
                isEnabled: canCheckForUpdates
            ) {
                onCommand(.checkForUpdates)
            }
            TrayDivider()
            TrayListRow(title: L10n.text("tray.about"), icon: .about, detail: appVersionLabel) {
                onCommand(.showAbout)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.32), lineWidth: 0.6)
        )
    }

    private var quitOrbit: some View {
        Button(role: .destructive) {
            onCommand(.quit)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: TrayPanelIcon.quit.systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OrbitalPalette.red)
                    .frame(width: 22, height: 22)
                    .background(OrbitalPalette.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(L10n.text("menu.quit"))
                    .font(.system(size: 12.2, weight: .medium))
                    .foregroundStyle(OrbitalPalette.red.opacity(0.82))

                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(OrbitalPalette.red.opacity(0.10), lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }.clickCursor()
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .accessibilityLabel(L10n.text("menu.quit"))
    }

    private var selectedCaptureQuality: CaptureQuality {
        CaptureQuality(rawValue: captureQualityRawValue) ?? .defaultValue
    }

    private var captureQualityBinding: Binding<CaptureQuality> {
        Binding(
            get: { selectedCaptureQuality },
            set: { captureQualityRawValue = $0.rawValue }
        )
    }
}

private enum TrayCommandTileStyle {
    case large
    case compact
}

private struct QualityRulerControl: View {
    @Binding var selection: CaptureQuality

    var body: some View {
        HStack(spacing: 1) {
            ForEach(CaptureQuality.allCases) { quality in
                Button {
                    selection = quality
                } label: {
                    Text(shortLabel(for: quality))
                        .font(.system(size: 9.5, weight: quality == selection ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(quality == selection ? Color.white : OrbitalPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background(
                            quality == selection ? OrbitalPalette.blue : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }.clickCursor()
                .buttonStyle(.plain)
                .accessibilityLabel(quality.title)
            }
        }
        .padding(2)
        .background(OrbitalPalette.nodeFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("preferences.outputQuality"))
    }

    private func shortLabel(for quality: CaptureQuality) -> String {
        switch quality {
        case .native: "Retina"
        case .hd720: "720"
        case .fullHD1080: "1080"
        case .qhd2K: "2K"
        case .uhd4K: "4K"
        case .uhd8K: "8K"
        }
    }
}

private struct TrayModuleShell<Content: View>: View {
    let title: String
    let tone: TrayPanelTone
    var contentPadding: CGFloat = 5
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OrbitalPalette.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            content()
                .padding(contentPadding)
        }
        .padding(6)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(OrbitalPalette.nodeEdge.opacity(0.34), lineWidth: 0.6)
        )
    }
}

private struct TrayCommandTile: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let title: String
    let icon: TrayPanelIcon
    var detail: String? = nil
    let tone: TrayPanelTone
    let style: TrayCommandTileStyle
    var isEnabled = true
    var role: ButtonRole? = nil
    var helpText: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    private var iconSize: CGFloat {
        switch style {
        case .large: 24
        case .compact: 22
        }
    }

    private var minHeight: CGFloat {
        switch style {
        case .large: 56
        case .compact: 40
        }
    }

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tone.color.opacity(isHovering ? 0.12 : 0.07))

                    Image(systemName: icon.systemName)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: style == .large ? 15 : 13, weight: .semibold))
                        .foregroundStyle(tone.color)
                }
                .frame(width: iconSize, height: iconSize)

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: style == .large ? 9.4 : 9.2, weight: .semibold))
                        .foregroundStyle(OrbitalPalette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(style == .large ? 2 : 1)
                        .minimumScaleFactor(0.72)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 9.2, weight: .medium, design: .rounded))
                            .foregroundStyle(OrbitalPalette.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? tone.color.opacity(0.07) : Color.white.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tone.color.opacity(isHovering ? 0.70 : 0.22), lineWidth: icon == .captureRegion ? 1.0 : 0.55)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }.clickCursor()
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: " "))
        .onHover { isHovering = $0 && isEnabled }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
    }
}

private struct TrayToggleTile: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let title: String
    let icon: TrayPanelIcon
    @Binding var isOn: Bool
    let width: CGFloat
    let height: CGFloat

    @State private var isHovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon.systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isOn ? OrbitalPalette.blue : OrbitalPalette.secondaryText)
                    .frame(width: 22, height: 22)
                    .background((isOn ? OrbitalPalette.blue : OrbitalPalette.nodeEdge).opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(title)
                    .font(.system(size: 11.3, weight: .medium))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(1)

                Spacer(minLength: 6)

                TraySwitch(isOn: isOn)
            }
            .frame(height: 30)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }.clickCursor()
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
        }
        .onHover { isHovering = $0 }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: isOn)
    }
}

private struct TraySwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? OrbitalPalette.blue : OrbitalPalette.nodeEdge.opacity(0.36))
            .frame(width: 31, height: 17)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .padding(2)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            }
    }
}

private struct TrayDivider: View {
    var body: some View {
        Rectangle()
            .fill(OrbitalPalette.nodeEdge.opacity(0.28))
            .frame(height: 0.5)
            .padding(.leading, 38)
    }
}

private struct TraySectionBreak: View {
    var body: some View {
        Rectangle()
            .fill(OrbitalPalette.nodeEdge.opacity(0.32))
            .frame(height: 0.5)
            .padding(.vertical, 2)
    }
}

private struct TrayListRow: View {
    let title: String
    let icon: TrayPanelIcon
    var detail: String? = nil
    var isEnabled = true
    var rowHeight: CGFloat = 22
    var isExpanded: Bool? = nil
    let action: () -> Void

    @State private var isHovering = false

    private var usesAccentIcon: Bool {
        isHovering || icon == .quickStart
    }

    private var iconForegroundColor: Color {
        usesAccentIcon ? OrbitalPalette.cyan : OrbitalPalette.secondaryText
    }

    private var iconBackgroundColor: Color {
        usesAccentIcon ? OrbitalPalette.cyan.opacity(0.075) : OrbitalPalette.nodeEdge.opacity(0.055)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon.systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12.8, weight: .semibold))
                    .foregroundStyle(iconForegroundColor)
                    .frame(width: 23, height: 23)
                    .background(iconBackgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let detail {
                    Text(detail)
                        .font(.system(size: 10.8, weight: .medium))
                        .foregroundStyle(OrbitalPalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9.6, weight: .semibold))
                    .foregroundStyle(OrbitalPalette.secondaryText.opacity(0.82))
                    .rotationEffect(.degrees(isExpanded == true ? 90 : 0))
            }
            .frame(height: rowHeight)
            .padding(.horizontal, 4)
            .background(isHovering ? OrbitalPalette.blue.opacity(0.055) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }.clickCursor()
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: " "))
        .accessibilityValue(isExpanded.map { L10n.text($0 ? "common.enabled" : "common.disabled") } ?? "")
        .onHover { isHovering = $0 && isEnabled }
    }
}

private struct TrayPanelContentHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TrayActionCell: View {
    let title: String
    let icon: TrayPanelIcon
    var detail: String? = nil
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon.systemName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 11.8, weight: .semibold))
                    .foregroundStyle(icon.tone.color)
                    .frame(width: 21, height: 21)
                    .background(icon.tone.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .font(.system(size: 10.8, weight: .medium))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 2)

                if let detail {
                    Text(detail)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OrbitalPalette.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 25)
            .background(isHovering ? OrbitalPalette.blue.opacity(0.06) : Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OrbitalPalette.nodeEdge.opacity(isHovering ? 0.40 : 0.22), lineWidth: 0.55)
            )
        }.clickCursor()
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .onHover { isHovering = $0 && isEnabled }
    }
}

private struct TrayNoticeRow: View {
    let title: String
    let icon: TrayPanelIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon.systemName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(icon.tone.color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OrbitalPalette.text)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(OrbitalPalette.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(icon.tone.color.opacity(0.24), lineWidth: 0.6)
            )
        }.clickCursor()
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct TrayUpdateNotice: View {
    let notice: UpdateNotice
    let installAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [OrbitalPalette.green, OrbitalPalette.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: TrayPanelIcon.updateAvailable.systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .shadow(color: OrbitalPalette.green.opacity(0.18), radius: 6, y: 2)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("tray.update.available.title"))
                        .font(.system(size: 12.8, weight: .bold))
                        .foregroundStyle(OrbitalPalette.text)
                        .lineLimit(1)

                    Text(L10n.text("tray.update.available.message", notice.version))
                        .font(.system(size: 11.2, weight: .medium))
                        .foregroundStyle(OrbitalPalette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Button(action: installAction) {
                        Text(L10n.text("tray.update.install"))
                            .font(.system(size: 11.2, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 27)
                            .background(OrbitalPalette.green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }.clickCursor()
                    .buttonStyle(.plain)

                    Button(action: dismissAction) {
                        Text(L10n.text("tray.update.later"))
                            .font(.system(size: 11.2, weight: .semibold))
                            .foregroundStyle(OrbitalPalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, minHeight: 27)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(OrbitalPalette.nodeEdge.opacity(0.34), lineWidth: 0.6)
                            )
                    }.clickCursor()
                    .buttonStyle(.plain)
                }
                .frame(height: 27)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [OrbitalPalette.green.opacity(0.11), Color.white.opacity(0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(OrbitalPalette.green.opacity(0.24), lineWidth: 0.6)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct TraySolCraftedBadge: View {
    private let gold = Color(red: 0.84, green: 0.69, blue: 0.29)

    var body: some View {
        HStack(spacing: 8) {
            Text("CRAFTED WITH")
                .foregroundStyle(OrbitalPalette.secondaryText.opacity(0.66))

            Text("GPT-5.6 SOL")
                .foregroundStyle(gold)
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .tracking(2.4)
        .frame(maxWidth: .infinity, minHeight: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PinboardShot, crafted with GPT-5.6 Sol")
    }
}

struct TrayPanelBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [OrbitalPalette.backgroundTop, OrbitalPalette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image("TrayPanelBackdropTexture")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.22)
                    .blendMode(.multiply)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .overlay(Color.white.opacity(0.70))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OrbitalPalette.nodeEdge.opacity(0.42), lineWidth: 0.55)
            )
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .ignoresSafeArea()
    }
}
