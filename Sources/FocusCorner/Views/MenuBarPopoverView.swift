import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared
    @ObservedObject private var timerManager = FocusTimerManager.shared
    @ObservedObject private var launchManager = LaunchAgentManager.shared
    @ObservedObject private var devManager = DevChannelManager.shared

    @State private var quickTaskText: String = ""
    @State private var quickTaskDays: Int = 1

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection

            Divider().overlay(Color.white.opacity(0.12))

            // 1. Live Focus Timer Control Card (Singular & Exam)
            timerQuickControlSection

            // 2. Window Visibility Cards (Tasks & RPA)
            HStack(spacing: 8) {
                hudToggleCard(
                    title: "Vazifalar & Timer",
                    subtitle: "\(storage.tasks.filter { !$0.isCompleted }.count) ta faol",
                    icon: "checklist",
                    isActive: windowController.isNotesVisible,
                    accent: .cyan,
                    action: { windowController.toggleNotesPanel() }
                )

                hudToggleCard(
                    title: "Bloknot (⌥Space)",
                    subtitle: "Insight • Qayd • Journal",
                    icon: "book.pages.fill",
                    isActive: windowController.isNotesVisible,
                    accent: .yellow,
                    action: { windowController.SummonNotebookViaShortcut() }
                )

                hudToggleCard(
                    title: "Terminal (⌘⇧K)",
                    subtitle: "CLI & Backup",
                    icon: "terminal.fill",
                    isActive: windowController.isNotesVisible,
                    accent: .green,
                    action: { windowController.SummonTerminalViaShortcut() }
                )
            }

            // 3. Quick Add Task with Duration
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    TextField("Tezkor vazifa qo'shish...", text: $quickTaskText, onCommit: submitQuickMenuTask)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4.5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Picker("", selection: $quickTaskDays) {
                        Text("Bugun").tag(1)
                        Text("3k").tag(3)
                        Text("7k").tag(7)
                        Text("14k").tag(14)
                    }
                    .labelsHidden()
                    .frame(width: 58)

                    Button(action: submitQuickMenuTask) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 4. Opacity & Stealth Row
            HStack(spacing: 8) {
                Button(windowController.isStealthHidden ? "👁 Ko'rsatish" : "👁 Yashirish") {
                    windowController.toggleStealthHideAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(windowController.isStealthHidden ? Color.green.opacity(0.28) : Color.white.opacity(0.10))
                .foregroundColor(windowController.isStealthHidden ? .green : .white)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Slider(
                    value: Binding(
                        get: { storage.settings.notesOpacity },
                        set: { val in
                            storage.settings.notesOpacity = val
                            storage.settings.rulesOpacity = val
                            storage.saveSettings()
                            windowController.applyWindowLayerAndOpacitySettings()
                        }
                    ),
                    in: 0.35...1.0
                )

                Text("\(Int(storage.settings.notesOpacity * 100))%")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 30, alignment: .trailing)
            }

            Divider().overlay(Color.white.opacity(0.12))

            footerBar
        }
        .padding(13)
        .frame(width: 345)
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .environment(\.colorScheme, .dark)
        .onAppear {
            launchManager.refreshStatus()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("FocusCorner v5.2")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("SAT: \(storage.satTracker.totalSATScore)/1600 • ExAcc: \(storage.formatPoints(storage.exAcc.totalStandardCharge))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.cyan)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Toggle("", isOn: Binding(
                    get: { launchManager.isAutostartEnabled },
                    set: { val in launchManager.setAutostart(enabled: val) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                Text(launchManager.isAutostartEnabled ? "Autorun: ON" : "Autorun: OFF")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(launchManager.isAutostartEnabled ? .green : .white.opacity(0.5))
            }
        }
    }

    private var timerQuickControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("⏱ FOKUS TIMER (ZEN MODE)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                if timerManager.isActive {
                    Text(timerManager.currentHeaderBadge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.cyan)
                }
            }

            if timerManager.isActive {
                HStack(spacing: 8) {
                    Text(timerManager.formattedTime)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Button(timerManager.isPaused ? "▶ Davom" : "⏸ Pauza") {
                        timerManager.togglePause()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)

                    if timerManager.config.mode == .exam {
                        Button("⏭ Part") {
                            timerManager.skipToNextPart()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("⏹ Stop") {
                        timerManager.stopTimer(completedNaturally: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: { timerManager.startSingular(minutes: 25) }) {
                        Text("▶ 25m Singular")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.22))
                            .foregroundColor(.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)

                    Button(action: { timerManager.startSingular(minutes: 45) }) {
                        Text("▶ 45m Singular")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.22))
                            .foregroundColor(.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)

                    Button(action: { timerManager.startExam() }) {
                        Text("▶ Exam (\(timerManager.config.examParts.count)p)")
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.24))
                            .foregroundColor(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func hudToggleCard(
        title: String,
        subtitle: String,
        icon: String,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isActive ? accent : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                    Text(isActive ? "Ko'rinmoqda • \(subtitle)" : "Yashirilgan")
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isActive ? accent.opacity(0.18) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func submitQuickMenuTask() {
        let trimmed = quickTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.addTask(title: trimmed, source: .general, durationDays: quickTaskDays)
        quickTaskText = ""
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button(action: { _ = storage.copyGeminiSyncReportToClipboard() }) {
                Label(String(format: "RAM: %.1f MB", devManager.memoryFootprintMB), systemImage: "memorychip")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
            }
            .buttonStyle(.plain)

            Spacer()

            // Subtle Developer / Maintenance Menu
            Menu {
                Button("🛡 To'liq Snapshot Backup Olish") {
                    _ = BackupManager.shared.createSnapshot(reason: "MenuBar Backup", silent: false)
                }
                Button("📦 ZIP Zahira Eksport (Downloads)") {
                    _ = BackupManager.shared.exportFullBackupZipToDownloads()
                }
                Button("📂 ~/.focus_corner papkasini ochish") {
                    NSWorkspace.shared.open(storage.baseDirURL)
                }
                Button("🧹 Kesh fayllarini tozalash") {
                    devManager.cleanStaleCachesAndTempFiles()
                }
                Divider()
                Button("⚡ Release Rebuild") {
                    devManager.triggerHotRebuild(channel: "release")
                }
                Button("🛠 Dev Rebuild") {
                    devManager.triggerHotRebuild(channel: "dev")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 3) {
                    Image(systemName: "power")
                    Text("Chiqish")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }
}
