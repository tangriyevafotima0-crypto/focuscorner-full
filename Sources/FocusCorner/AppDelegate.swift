import AppKit
import SwiftUI
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStandardEditMainMenu()

        let isAutostart = CommandLine.arguments.contains("--autostart")
        setupMenuBarPopoverApp()
        WindowController.shared.initializeWindows(isAutostart: isAutostart)
        _ = EyeCareManager.shared
        _ = BackupManager.shared
        BackupManager.shared.createAutoBackupIfNeeded(reason: "Ilova Ishga Tushishi")

        if !LaunchAgentManager.shared.isAutostartEnabled {
            LaunchAgentManager.shared.setAutostart(enabled: true)
        }

        Publishers.CombineLatest4(
            StorageManager.shared.$satTracker,
            StorageManager.shared.$exAcc,
            WindowController.shared.$snoozeRemainingSeconds,
            FocusTimerManager.shared.$remainingSeconds
        )
        .combineLatest(
            FocusTimerManager.shared.$isActive,
            EyeCareManager.shared.$isBreakActive,
            EyeCareManager.shared.$breakRemainingSeconds
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] combined, isTimerActive, isEyeBreak, eyeSecs in
            let (sat, exacc, snooze, _) = combined
            self?.updateStatusButtonTitle(
                satScore: sat.totalSATScore,
                exAccCharge: Int(exacc.totalStandardCharge),
                snoozeSeconds: snooze,
                isTimerActive: isTimerActive,
                isEyeBreakActive: isEyeBreak,
                eyeBreakSeconds: eyeSecs
            )
        }
        .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            DevChannelManager.shared.silentMemoryTrim()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NotebookManager.shared.flushPendingSaveImmediately()
        StorageManager.shared.saveTasks()
        StorageManager.shared.saveSettings()
    }

    /// Essential for accessory apps: enables Cmd+V (Paste), Cmd+C (Copy), Cmd+X (Cut), Cmd+A (Select All), Cmd+Z (Undo)
    /// across all SwiftUI TextFields, Terminal input, and NSTextView!
    private func setupStandardEditMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit FocusCorner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBarPopoverApp() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 350, height: 440)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusButtonTitle(
            satScore: StorageManager.shared.satTracker.totalSATScore,
            exAccCharge: Int(StorageManager.shared.exAcc.totalStandardCharge),
            snoozeSeconds: 0,
            isTimerActive: FocusTimerManager.shared.isActive,
            isEyeBreakActive: false,
            eyeBreakSeconds: 0
        )
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            LaunchAgentManager.shared.refreshStatus()
            DevChannelManager.shared.refreshMemoryUsage()
            popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    public func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        DevChannelManager.shared.silentMemoryTrim()
    }

    private func updateStatusButtonTitle(
        satScore: Int,
        exAccCharge: Int,
        snoozeSeconds: Int,
        isTimerActive: Bool,
        isEyeBreakActive: Bool,
        eyeBreakSeconds: Int
    ) {
        guard let button = statusItem?.button else { return }
        if isEyeBreakActive {
            let ec = EyeCareManager.shared
            if ec.activeBreakKind == .macro5m {
                button.title = String(format: "🌿 Tanaffus %d:%02d", eyeBreakSeconds / 60, eyeBreakSeconds % 60)
            } else {
                button.title = "👁 Ko'z dami: \(eyeBreakSeconds)s"
            }
        } else if isTimerActive {
            let tm = FocusTimerManager.shared
            let icon = tm.isPaused ? "⏸" : (tm.isBreakPhase ? "☕" : "⏱")
            if tm.config.mode == .exam {
                button.title = "\(icon) \(tm.formattedTime) (\(tm.currentPartIndex + 1)/\(tm.config.examParts.count))"
            } else {
                button.title = "\(icon) \(tm.formattedTime)"
            }
        } else if snoozeSeconds > 0 {
            let m = snoozeSeconds / 60
            let s = snoozeSeconds % 60
            button.title = String(format: "⏳ %02d:%02d", m, s)
        } else {
            button.title = "🎯 \(satScore) ⚡\(exAccCharge)"
        }
    }
}
