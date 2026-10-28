import AppKit
import SwiftUI
import Combine
import Carbon

private func focusCornerHotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        theEvent,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if status == noErr {
        let id = hotKeyID.id
        Task { @MainActor in
            if id == 1 || id == 2 {
                WindowController.shared.SummonNotebookViaShortcut()
            } else if id == 4 {
                WindowController.shared.SummonTerminalViaShortcut()
            } else if id == 3 {
                if FocusTimerManager.shared.isActive {
                    FocusTimerManager.shared.togglePause()
                } else {
                    FocusTimerManager.shared.startSingular()
                }
            }
        }
    }
    return noErr
}

@MainActor
public final class WindowController: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = WindowController()

    public private(set) var rulesPanel: FloatingPanel?
    public private(set) var notesPanel: FloatingPanel?
    public private(set) var timerPanel: FloatingPanel?
    public private(set) var eyeCarePanel: FloatingPanel?
    public private(set) var morningPromptPanel: FloatingPanel?

    @Published public var isRulesVisible: Bool = false
    @Published public var isNotesVisible: Bool = true
    @Published public var isTimerHUDVisible: Bool = false
    @Published public var isStealthHidden: Bool = false
    @Published public var snoozeRemainingSeconds: Int = 0
    @Published public var requestedMainTab: CalmMainTab? = nil

    private var preTimerNotesVisible: Bool = true
    private var preTimerRulesVisible: Bool = false

    private var snoozeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var hotKeyRefOptSpace: EventHotKeyRef?
    private var hotKeyRefCmdShiftB: EventHotKeyRef?
    private var hotKeyRefCmdShiftK: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    private let edgeInset: CGFloat = 22.0
    public let collapsedHeaderHeight: CGFloat = 46.0
    private let standardTimerSize = NSSize(width: 336, height: 134)
    private let compactTimerPillSize = NSSize(width: 232, height: 46)

    private override init() {
        super.init()
        setupNotifications()
        setupGlobalShortcuts()
        registerCarbonGlobalHotKeys()
    }

    // MARK: - Lazy Window Initialization (Only 1 Window Allocated at Launch!)

    public func initializeWindows(isAutostart: Bool) {
        ensureAndShowNotesPanel()
    }

    private func ensureAndShowNotesPanel() {
        let storage = StorageManager.shared
        let level = storage.settings.windowLevel.nsWindowLevel
        let notesSize = effectiveNotesSize()
        let notesOrigin = calculateInitialNotesOrigin(size: notesSize)

        if notesPanel == nil {
            let nPanel = FloatingPanel(
                contentRect: NSRect(origin: notesOrigin, size: notesSize),
                level: level,
                movable: true
            )
            nPanel.delegate = self
            self.notesPanel = nPanel
        }
        guard let panel = notesPanel else { return }
        if panel.contentView == nil {
            panel.contentView = FixedSizeHostingView(rootView: NotesView())
        }
        panel.minSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.contentMinSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.setFrame(NSRect(origin: panel.frame.origin, size: notesSize), display: true, animate: false)
        panel.alphaValue = storage.settings.isGhostClickThrough ? 0.22 : storage.settings.notesOpacity
        panel.ignoresMouseEvents = storage.settings.isGhostClickThrough
        panel.level = level
        panel.orderFrontRegardless()
        self.isNotesVisible = true
    }

    // MARK: - Harmless Non-Activating EyeCare Toast Panel

    public func showEyeCareToastPanel() {
        // If main notesPanel is visible AND expanded, EyeCareBannerHUDView renders cleanly inside NotesView.
        // If notesPanel is collapsed or hidden, show a standalone floating toast banner so collapsed bar never stretches!
        if isNotesVisible && !StorageManager.shared.settings.isNotesCollapsed {
            return
        }

        let bannerSize = NSSize(width: 440, height: 74)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - bannerSize.width / 2,
            y: screenFrame.maxY - bannerSize.height - 18
        )

        if eyeCarePanel == nil {
            let ePanel = FloatingPanel(
                contentRect: NSRect(origin: origin, size: bannerSize),
                level: .statusBar,
                movable: true
            )
            ePanel.becomesKeyOnlyIfNeeded = true
            self.eyeCarePanel = ePanel
        }
        guard let panel = eyeCarePanel else { return }
        panel.contentView = FixedSizeHostingView(rootView: EyeCareBannerHUDView())
        panel.setFrame(NSRect(origin: origin, size: bannerSize), display: true, animate: true)
        panel.orderFrontRegardless()
        enforceCollapsedHeightIfNeeded()
    }

    public func hideEyeCareToastPanel() {
        eyeCarePanel?.orderOut(nil)
        eyeCarePanel?.contentView = nil
        eyeCarePanel = nil
        enforceCollapsedHeightIfNeeded()
        DevChannelManager.shared.silentMemoryTrim()
    }

    /// Guarantees that if the user is in collapsed mini-bar mode, the window height stays strictly 46pt with zero top black gap.
    public func enforceCollapsedHeightIfNeeded() {
        let storage = StorageManager.shared
        if storage.settings.isNotesCollapsed, let panel = notesPanel {
            let targetW = max(460, CGFloat(storage.settings.notesWidth))
            let targetH = collapsedHeaderHeight
            if abs(panel.frame.height - targetH) > 1.0 || abs(panel.frame.width - targetW) > 1.0 {
                let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                panel.minSize = NSSize(width: 240, height: targetH)
                panel.contentMinSize = NSSize(width: 240, height: targetH)
                panel.setFrame(
                    NSRect(x: topLeft.x, y: topLeft.y - targetH, width: targetW, height: targetH),
                    display: true,
                    animate: false
                )
            }
        }
        if storage.settings.isRulesCollapsed, let rPanel = rulesPanel {
            let targetW = max(320, CGFloat(storage.settings.rulesWidth))
            let targetH = collapsedHeaderHeight
            if abs(rPanel.frame.height - targetH) > 1.0 {
                let topLeft = NSPoint(x: rPanel.frame.minX, y: rPanel.frame.maxY)
                rPanel.minSize = NSSize(width: 240, height: targetH)
                rPanel.contentMinSize = NSSize(width: 240, height: targetH)
                rPanel.setFrame(
                    NSRect(x: topLeft.x, y: topLeft.y - targetH, width: targetW, height: targetH),
                    display: true,
                    animate: false
                )
            }
        }
    }

    // MARK: - Instant Bloknot & Terminal Summoners

    public func SummonTerminalViaShortcut() {
        let storage = StorageManager.shared
        if storage.settings.isNotesCollapsed {
            storage.settings.isNotesCollapsed = false
            storage.saveSettings()
            updateNotesPanelFrame(animated: true)
        }
        isStealthHidden = false
        requestedMainTab = .terminal
        showNotesPanel(focusInput: true)
    }

    public func SummonNotebookViaShortcut() {
        let storage = StorageManager.shared
        if storage.settings.isNotesCollapsed {
            storage.settings.isNotesCollapsed = false
            storage.saveSettings()
            updateNotesPanelFrame(animated: true)
        }
        isStealthHidden = false
        requestedMainTab = .notebook
        showNotesPanel(focusInput: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if let tv = NotebookManager.shared.activeTextView {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    // MARK: - Zen Timer Mode Transitions

    public func enterZenTimerMode() {
        let timerCfg = FocusTimerManager.shared.config
        NotebookManager.shared.flushPendingSaveImmediately()

        preTimerNotesVisible = isNotesVisible
        preTimerRulesVisible = isRulesVisible

        if timerCfg.hideTasksWhenTimerStarts {
            notesPanel?.orderOut(nil)
            notesPanel?.contentView = nil
            isNotesVisible = false
        }

        if timerCfg.adaptiveRPAWhenTimerStarts {
            hideRulesPanel()
        }

        let targetSize = FocusTimerManager.shared.isCompactPill ? compactTimerPillSize : standardTimerSize
        let origin = calculateInitialTimerOrigin(size: targetSize)
        let level = StorageManager.shared.settings.windowLevel.nsWindowLevel

        if timerPanel == nil {
            let tPanel = FloatingPanel(
                contentRect: NSRect(origin: origin, size: targetSize),
                level: level,
                movable: true
            )
            tPanel.delegate = self
            self.timerPanel = tPanel
        }
        if let tPanel = timerPanel {
            tPanel.contentView = FixedSizeHostingView(rootView: FocusTimerHUDView())
            tPanel.alphaValue = StorageManager.shared.settings.notesOpacity
            tPanel.setFrame(NSRect(origin: origin, size: targetSize), display: true, animate: true)
            tPanel.level = level
            tPanel.orderFrontRegardless()
            isTimerHUDVisible = true
        }
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func exitZenTimerMode() {
        timerPanel?.orderOut(nil)
        timerPanel?.contentView = nil
        timerPanel = nil
        isTimerHUDVisible = false

        if preTimerNotesVisible {
            showNotesPanel(focusInput: false)
        }
        if preTimerRulesVisible {
            showRulesPanel()
        }
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func setTimerCompactPill(_ compact: Bool) {
        FocusTimerManager.shared.isCompactPill = compact
        guard let tPanel = timerPanel else { return }
        let currentTopRight = NSPoint(x: tPanel.frame.maxX, y: tPanel.frame.maxY)
        let newSize = compact ? compactTimerPillSize : standardTimerSize
        let newOrigin = NSPoint(x: currentTopRight.x - newSize.width, y: currentTopRight.y - newSize.height)
        tPanel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: true)
    }

    // MARK: - Morning Startup Prompt

    public func showMorningPrompt() {
        if let existing = morningPromptPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let promptSize = NSSize(width: 430, height: 245)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - promptSize.width / 2,
            y: screenFrame.midY - promptSize.height / 2
        )

        let pPanel = FloatingPanel(
            contentRect: NSRect(origin: origin, size: promptSize),
            level: .modalPanel,
            movable: true
        )
        pPanel.contentView = FixedSizeHostingView(
            rootView: MorningPromptView(
                onYes: { [weak self] in
                    guard let self = self else { return }
                    StorageManager.shared.settings.lastPromptDate = TaskItem.todayString()
                    StorageManager.shared.saveSettings()
                    self.morningPromptPanel?.orderOut(nil)
                    self.morningPromptPanel?.contentView = nil
                    self.morningPromptPanel = nil
                    self.showNotesPanel(focusInput: true)
                },
                onNo: { [weak self] in
                    guard let self = self else { return }
                    StorageManager.shared.settings.lastPromptDate = TaskItem.todayString()
                    StorageManager.shared.saveSettings()
                    self.morningPromptPanel?.orderOut(nil)
                    self.morningPromptPanel?.contentView = nil
                    self.morningPromptPanel = nil
                    self.hideNotesPanel()
                }
            )
        )
        self.morningPromptPanel = pPanel
        pPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Positioning & Sizing

    private func effectiveRulesSize() -> NSSize {
        let s = StorageManager.shared.settings
        let width = max(360, CGFloat(s.rulesWidth))
        let height = s.isRulesCollapsed ? collapsedHeaderHeight : max(210, CGFloat(s.rulesHeight))
        return NSSize(width: width, height: height)
    }

    private func effectiveNotesSize() -> NSSize {
        let s = StorageManager.shared.settings
        let width = max(460, CGFloat(s.notesWidth))
        let height = s.isNotesCollapsed ? collapsedHeaderHeight : max(480, CGFloat(s.notesHeight))
        return NSSize(width: width, height: height)
    }

    public func expandNotesPanel(animated: Bool = true) {
        let storage = StorageManager.shared
        guard storage.settings.isNotesCollapsed else { return }
        storage.settings.isNotesCollapsed = false
        storage.saveSettings()
        updateNotesPanelFrame(animated: animated)
    }

    private func calculateInitialRulesOrigin(size: NSSize) -> NSPoint {
        let s = StorageManager.shared.settings
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 80, y: 80)
        }
        let visible = screen.visibleFrame
        if let rx = s.rulesOriginX, let ry = s.rulesOriginY {
            let clampedX = max(visible.minX + 8, min(CGFloat(rx), visible.maxX - size.width - 8))
            let clampedY = max(visible.minY + 8, min(CGFloat(ry), visible.maxY - size.height - 8))
            return NSPoint(x: clampedX, y: clampedY)
        }
        return calculateCornerOrigin(for: s.pinnedCorner, size: size)
    }

    private func calculateInitialTimerOrigin(size: NSSize) -> NSPoint {
        let cfg = FocusTimerManager.shared.config
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 300, y: 600)
        }
        let visible = screen.visibleFrame
        if let tx = cfg.timerOriginX, let ty = cfg.timerOriginY {
            let clampedX = max(visible.minX + 8, min(CGFloat(tx), visible.maxX - size.width - 8))
            let clampedY = max(visible.minY + 8, min(CGFloat(ty), visible.maxY - size.height - 8))
            return NSPoint(x: clampedX, y: clampedY)
        }
        return NSPoint(
            x: visible.maxX - size.width - edgeInset,
            y: visible.maxY - size.height - edgeInset
        )
    }

    public func calculateCornerOrigin(for corner: CornerPosition, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 100, y: 100)
        }
        let visible = screen.visibleFrame
        switch corner {
        case .topLeft:
            return NSPoint(x: visible.minX + edgeInset, y: visible.maxY - size.height - edgeInset)
        case .topRight:
            return NSPoint(x: visible.maxX - size.width - edgeInset, y: visible.maxY - size.height - edgeInset)
        case .bottomLeft:
            return NSPoint(x: visible.minX + edgeInset, y: visible.minY + edgeInset)
        case .bottomRight:
            return NSPoint(x: visible.maxX - size.width - edgeInset, y: visible.minY + edgeInset)
        }
    }

    private func calculateInitialNotesOrigin(size: NSSize) -> NSPoint {
        let s = StorageManager.shared.settings
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: 200, y: 200)
        }
        let visible = screen.visibleFrame

        if let ox = s.notesOriginX, let oy = s.notesOriginY {
            let clampedX = max(visible.minX + 10, min(CGFloat(ox), visible.maxX - size.width - 10))
            let clampedY = max(visible.minY + 10, min(CGFloat(oy), visible.maxY - size.height - 10))
            return NSPoint(x: clampedX, y: clampedY)
        }

        let defaultX = visible.minX + edgeInset
        let defaultY = visible.maxY - size.height - edgeInset
        return NSPoint(x: defaultX, y: defaultY)
    }

    public func snapRulesPanelToCorner(_ corner: CornerPosition, animated: Bool = true) {
        let storage = StorageManager.shared
        storage.settings.pinnedCorner = corner
        storage.RPAResetCustomOrigin()
        storage.saveSettings()

        guard let panel = rulesPanel else { return }
        let size = effectiveRulesSize()
        let origin = calculateCornerOrigin(for: corner, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
    }

    public func setRulesPinned(_ pinned: Bool) {
        let storage = StorageManager.shared
        storage.settings.isRulesPinned = pinned
        storage.saveSettings()
        rulesPanel?.allowBackgroundDrag = true
        if pinned {
            snapRulesPanelToCorner(storage.settings.pinnedCorner, animated: true)
        }
    }

    // MARK: - Resizing & Collapse

    public func applyRulesSizePreset(_ preset: HUDSizePreset) {
        let storage = StorageManager.shared
        let dims = preset.rulesDimensions
        storage.settings.rulesWidth = Double(dims.width)
        storage.settings.rulesHeight = Double(dims.height)
        storage.settings.isRulesCollapsed = false
        storage.saveSettings()
        if let panel = rulesPanel {
            let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - dims.height, width: dims.width, height: dims.height), display: true, animate: true)
        }
    }

    public func applyNotesSizePreset(_ preset: HUDSizePreset) {
        let storage = StorageManager.shared
        let dims = preset.notesDimensions
        storage.settings.notesWidth = Double(dims.width)
        storage.settings.notesHeight = Double(dims.height)
        storage.settings.isNotesCollapsed = false
        storage.saveSettings()
        updateNotesPanelFrame(animated: true)
    }

    public func resizeRulesPanel(byDelta deltaSize: NSSize) {
        let storage = StorageManager.shared
        guard !storage.settings.isRulesCollapsed, let panel = rulesPanel else { return }
        let newW = max(360, min(620, storage.settings.rulesWidth + Double(deltaSize.width)))
        let newH = max(210, min(720, storage.settings.rulesHeight + Double(deltaSize.height)))
        storage.settings.rulesWidth = newW
        storage.settings.rulesHeight = newH

        let currentFrame = panel.frame
        let newOriginY = currentFrame.maxY - CGFloat(newH)
        let newFrame = NSRect(x: currentFrame.minX, y: newOriginY, width: CGFloat(newW), height: CGFloat(newH))
        panel.setFrame(newFrame, display: true, animate: false)
        storage.settings.rulesOriginX = Double(newFrame.minX)
        storage.settings.rulesOriginY = Double(newFrame.minY)
        storage.saveSettings()
    }

    public func resizeNotesPanel(byDelta deltaSize: NSSize) {
        let storage = StorageManager.shared
        guard !storage.settings.isNotesCollapsed, let panel = notesPanel else { return }
        let newW = max(460, min(860, storage.settings.notesWidth + Double(deltaSize.width)))
        let newH = max(320, min(920, storage.settings.notesHeight + Double(deltaSize.height)))
        storage.settings.notesWidth = newW
        storage.settings.notesHeight = newH

        let currentFrame = panel.frame
        let newOriginY = currentFrame.maxY - CGFloat(newH)
        let newFrame = NSRect(x: currentFrame.minX, y: newOriginY, width: CGFloat(newW), height: CGFloat(newH))
        panel.setFrame(newFrame, display: true, animate: false)
        storage.settings.notesOriginX = Double(newFrame.minX)
        storage.settings.notesOriginY = Double(newFrame.minY)
        storage.saveSettings()
    }

    public func toggleRulesCollapsed() {
        let storage = StorageManager.shared
        storage.settings.isRulesCollapsed.toggle()
        storage.saveSettings()
        if let panel = rulesPanel {
            let currentTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            let newSize = effectiveRulesSize()
            panel.minSize = NSSize(width: 240, height: collapsedHeaderHeight)
            panel.contentMinSize = NSSize(width: 240, height: collapsedHeaderHeight)
            panel.setFrame(NSRect(x: currentTopLeft.x, y: currentTopLeft.y - newSize.height, width: newSize.width, height: newSize.height), display: true, animate: true)
        }
    }

    public func toggleNotesCollapsed() {
        let storage = StorageManager.shared
        storage.settings.isNotesCollapsed.toggle()
        storage.saveSettings()
        if storage.settings.isNotesCollapsed {
            storage.toastBanner = nil
        }
        updateNotesPanelFrame(animated: true)
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func updateNotesPanelFrame(animated: Bool) {
        guard let panel = notesPanel else { return }
        let currentTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let newSize = effectiveNotesSize()
        let newOrigin = NSPoint(x: currentTopLeft.x, y: currentTopLeft.y - newSize.height)
        panel.minSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.contentMinSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: animated)
        storageSaveOriginIfNeeded(panel: panel)
    }

    private func storageSaveOriginIfNeeded(panel: NSPanel) {
        let storage = StorageManager.shared
        storage.settings.notesOriginX = Double(panel.frame.minX)
        storage.settings.notesOriginY = Double(panel.frame.minY)
        storage.saveSettings()
    }

    // MARK: - Visibility & Lazy Memory Teardown

    public func showRulesPanel() {
        isStealthHidden = false
        let storage = StorageManager.shared
        let level = storage.settings.windowLevel.nsWindowLevel
        let rulesSize = effectiveRulesSize()
        let rulesOrigin = calculateInitialRulesOrigin(size: rulesSize)

        if rulesPanel == nil {
            let rPanel = FloatingPanel(
                contentRect: NSRect(origin: rulesOrigin, size: rulesSize),
                level: level,
                movable: true
            )
            rPanel.delegate = self
            self.rulesPanel = rPanel
        }
        guard let panel = rulesPanel else { return }
        if panel.contentView == nil {
            panel.contentView = FixedSizeHostingView(rootView: RulesView())
        }
        panel.minSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.contentMinSize = NSSize(width: 240, height: collapsedHeaderHeight)
        panel.setFrame(NSRect(origin: panel.frame.origin, size: rulesSize), display: true, animate: false)
        panel.alphaValue = storage.settings.isGhostClickThrough ? 0.22 : storage.settings.rulesOpacity
        panel.ignoresMouseEvents = storage.settings.isGhostClickThrough
        panel.orderFrontRegardless()
        isRulesVisible = true
    }

    public func hideRulesPanel() {
        rulesPanel?.orderOut(nil)
        rulesPanel?.contentView = nil
        rulesPanel = nil
        isRulesVisible = false
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func toggleRulesPanel() {
        if isRulesVisible { hideRulesPanel() } else { showRulesPanel() }
    }

    public func showNotesPanel(focusInput: Bool = false) {
        isStealthHidden = false
        ensureAndShowNotesPanel()
        if focusInput {
            notesPanel?.focusForTextInput()
        }
    }

    public func hideNotesPanel() {
        NotebookManager.shared.flushPendingSaveImmediately()
        notesPanel?.orderOut(nil)
        notesPanel?.contentView = nil
        isNotesVisible = false
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func toggleNotesPanel() {
        if isNotesVisible { hideNotesPanel() } else { showNotesPanel(focusInput: false) }
    }

    public func toggleStealthHideAll() {
        cancelSnoozeTimer()
        if isStealthHidden {
            isStealthHidden = false
            if FocusTimerManager.shared.isActive {
                enterZenTimerMode()
            } else {
                showNotesPanel(focusInput: false)
            }
        } else {
            NotebookManager.shared.flushPendingSaveImmediately()
            isStealthHidden = true
            hideRulesPanel()
            hideNotesPanel()
            timerPanel?.orderOut(nil)
            timerPanel?.contentView = nil
            isTimerHUDVisible = false
            DevChannelManager.shared.silentMemoryTrim()
        }
    }

    public func snoozeAllHUDs(forMinutes minutes: Int) {
        cancelSnoozeTimer()
        NotebookManager.shared.flushPendingSaveImmediately()
        isStealthHidden = true
        hideRulesPanel()
        hideNotesPanel()
        timerPanel?.orderOut(nil)
        timerPanel?.contentView = nil
        isTimerHUDVisible = false
        snoozeRemainingSeconds = minutes * 60

        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.snoozeRemainingSeconds > 1 {
                    self.snoozeRemainingSeconds -= 1
                } else {
                    self.cancelSnoozeTimer()
                    self.isStealthHidden = false
                    if FocusTimerManager.shared.isActive {
                        self.enterZenTimerMode()
                    } else {
                        self.showNotesPanel(focusInput: false)
                    }
                }
            }
        }
    }

    public func cancelSnoozeTimer() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        snoozeRemainingSeconds = 0
    }

    public func toggleGhostClickThrough() {
        let storage = StorageManager.shared
        storage.settings.isGhostClickThrough.toggle()
        storage.saveSettings()
        applyWindowLayerAndOpacitySettings()
    }

    public func applyWindowLayerAndOpacitySettings() {
        let s = StorageManager.shared.settings
        let level = s.windowLevel.nsWindowLevel

        rulesPanel?.level = level
        notesPanel?.level = level
        timerPanel?.level = level

        rulesPanel?.alphaValue = s.isGhostClickThrough ? 0.22 : s.rulesOpacity
        notesPanel?.alphaValue = s.isGhostClickThrough ? 0.22 : s.notesOpacity
        timerPanel?.alphaValue = s.isGhostClickThrough ? 0.35 : max(0.85, s.notesOpacity)

        rulesPanel?.ignoresMouseEvents = s.isGhostClickThrough
        notesPanel?.ignoresMouseEvents = s.isGhostClickThrough
        timerPanel?.ignoresMouseEvents = s.isGhostClickThrough

        reassertAlwaysOnTopOrder()
    }

    public func reassertAlwaysOnTopOrder() {
        guard !isStealthHidden else { return }
        let level = StorageManager.shared.settings.windowLevel.nsWindowLevel
        if isRulesVisible {
            rulesPanel?.level = level
            rulesPanel?.orderFrontRegardless()
        }
        if isNotesVisible {
            notesPanel?.level = level
            notesPanel?.orderFrontRegardless()
        }
        if isTimerHUDVisible {
            timerPanel?.level = level
            timerPanel?.orderFrontRegardless()
        }
    }

    // MARK: - Window Delegate

    public func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        let storage = StorageManager.shared
        if win == notesPanel {
            storage.settings.notesOriginX = Double(win.frame.minX)
            storage.settings.notesOriginY = Double(win.frame.minY)
            storage.saveSettings()
        } else if win == rulesPanel {
            storage.settings.rulesOriginX = Double(win.frame.minX)
            storage.settings.rulesOriginY = Double(win.frame.minY)
            storage.saveSettings()
        } else if win == timerPanel {
            FocusTimerManager.shared.config.timerOriginX = Double(win.frame.minX)
            FocusTimerManager.shared.config.timerOriginY = Double(win.frame.minY)
            FocusTimerManager.shared.saveConfig()
        }
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        let storage = StorageManager.shared
        if win == rulesPanel && !storage.settings.isRulesCollapsed {
            storage.settings.rulesWidth = Double(win.frame.width)
            storage.settings.rulesHeight = Double(win.frame.height)
            storage.settings.rulesOriginX = Double(win.frame.minX)
            storage.settings.rulesOriginY = Double(win.frame.minY)
            storage.saveSettings()
        } else if win == notesPanel && !storage.settings.isNotesCollapsed {
            storage.settings.notesWidth = Double(win.frame.width)
            storage.settings.notesHeight = Double(win.frame.height)
            storage.settings.notesOriginX = Double(win.frame.minX)
            storage.settings.notesOriginY = Double(win.frame.minY)
            storage.saveSettings()
        }
    }

    private func setupNotifications() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reassertAlwaysOnTopOrder() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reassertAlwaysOnTopOrder() }
            .store(in: &cancellables)
    }

    // MARK: - System-Wide Carbon Global HotKey Registration

    private func registerCarbonGlobalHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            focusCornerHotKeyCallback,
            1,
            &eventType,
            nil,
            &hotKeyEventHandler
        )

        let optSpaceID = EventHotKeyID(signature: OSType(0x46434E42), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            optSpaceID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefOptSpace
        )

        let cmdShiftBID = EventHotKeyID(signature: OSType(0x46434E42), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | shiftKey),
            cmdShiftBID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefCmdShiftB
        )

        let cmdShiftKID = EventHotKeyID(signature: OSType(0x46434E42), id: 4)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey | shiftKey),
            cmdShiftKID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRefCmdShiftK
        )
    }

    private func setupGlobalShortcuts() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option] && event.keyCode == 49 {
                Task { @MainActor in
                    self?.SummonNotebookViaShortcut()
                }
                return
            }
            guard flags == [.command, .shift],
                  let chars = event.charactersIgnoringModifiers?.lowercased() else { return }

            Task { @MainActor in
                switch chars {
                case "b":
                    self?.SummonNotebookViaShortcut()
                case "k":
                    self?.SummonTerminalViaShortcut()
                case "f":
                    self?.toggleNotesPanel()
                case "r":
                    self?.toggleRulesPanel()
                case "t":
                    if FocusTimerManager.shared.isActive {
                        FocusTimerManager.shared.togglePause()
                    } else {
                        FocusTimerManager.shared.startSingular()
                    }
                case "e":
                    EyeCareManager.shared.triggerMicroBreakNow()
                case "h":
                    self?.toggleStealthHideAll()
                default:
                    break
                }
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option] && event.keyCode == 49 {
                handler(event)
                return nil
            }
            if flags == [.command, .shift],
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               ["b", "k", "f", "r", "t", "e", "h"].contains(chars) {
                handler(event)
                return nil
            }
            return event
        }
    }
}
