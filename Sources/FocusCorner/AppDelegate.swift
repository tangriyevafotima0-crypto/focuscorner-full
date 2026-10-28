import AppKit
import SwiftUI
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let isAutostart = CommandLine.arguments.contains("--autostart")
        setupMenuBarPopoverApp()
        WindowController.shared.initializeWindows(isAutostart: isAutostart)

        if !LaunchAgentManager.shared.isAutostartEnabled {
            LaunchAgentManager.shared.setAutostart(enabled: true)
        }

        // Keep Menu Bar button synced with Active Focus Timer OR SAT/ExAcc scores
        Publishers.CombineLatest4(
            StorageManager.shared.$satTracker,
            StorageManager.shared.$exAcc,
            WindowController.shared.$snoozeRemainingSeconds,
            FocusTimerManager.shared.$remainingSeconds
        )
        .combineLatest(FocusTimerManager.shared.$isActive, FocusTimerManager.shared.$isPaused)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] combined, isTimerActive, isTimerPaused in
            let (sat, exacc, snooze, _) = combined
            self?.updateStatusButtonTitle(
                satScore: sat.totalSATScore,
                exAccCharge: Int(exacc.totalStandardCharge),
                snoozeSeconds: snooze,
                isTimerActive: isTimerActive,
                isTimerPaused: isTimerPaused
            )
        }
        .store(in: &cancellables)
    }

    private func setupMenuBarPopoverApp() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 350, height: 420)
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView())

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
            isTimerPaused: FocusTimerManager.shared.isPaused
        )
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            DevChannelManager.shared.refreshMemoryUsage()
            LaunchAgentManager.shared.refreshStatus()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusButtonTitle(
        satScore: Int,
        exAccCharge: Int,
        snoozeSeconds: Int,
        isTimerActive: Bool,
        isTimerPaused: Bool
    ) {
        guard let button = statusItem?.button else { return }
        if isTimerActive {
            let tm = FocusTimerManager.shared
            let icon = isTimerPaused ? "⏸" : (tm.isBreakPhase ? "☕" : "⏱")
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
