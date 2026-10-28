import SwiftUI
import AppKit

public enum TerminalSubMode: String, CaseIterable, Identifiable {
    case console = "Terminal"
    case backupCenter = "Backup & Tiklash"

    public var id: String { rawValue }
}

public struct TerminalTabView: View {
    @ObservedObject private var terminal = TerminalManager.shared
    @ObservedObject private var backup = BackupManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared

    @State private var subMode: TerminalSubMode = .console
    @State private var commandInput: String = ""
    @State private var isMultiLineMode: Bool = false
    @FocusState private var isCommandFocused: Bool

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 1. Sub-mode selector bar (>_ Terminal | 🛡 Backup & Tiklash) + Quick Actions
            HStack(spacing: 6) {
                ForEach(TerminalSubMode.allCases) { mode in
                    let isSel = (subMode == mode)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            subMode = mode
                        }
                        if mode == .backupCenter {
                            backup.refreshSnapshotsList()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: mode == .console ? "terminal.fill" : "externaldrive.badge.checkmark")
                                .font(.system(size: 10, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 10.5, weight: isSel ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSel
                                ? (mode == .console ? Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.22) : Color(red: 0.22, green: 0.84, blue: 0.52).opacity(0.22))
                                : Color.white.opacity(0.05)
                        )
                        .foregroundColor(
                            isSel
                                ? (mode == .console ? Color(red: 0.45, green: 0.78, blue: 1.00) : Color(red: 0.28, green: 0.90, blue: 0.58))
                                : .white.opacity(0.62)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // One-Click "Paste & Run" from Clipboard!
                Button(action: {
                    subMode = .console
                    terminal.runClipboardCommandImmediately()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Paste & Run")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.18))
                    .foregroundColor(Color(red: 0.45, green: 0.78, blue: 1.00))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Buferga (Clipboard) nusxalangan Python yoki Terminal kodni darhol ishga tushirish")

                // Instant Snapshot Button
                Button(action: {
                    _ = backup.createSnapshot(reason: "Tezkor Tugma", silent: false)
                }) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.84, blue: 0.52))
                        .frame(width: 24, height: 24)
                        .background(Color(red: 0.22, green: 0.84, blue: 0.52).opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Darhol to'liq Backup (Snapshot) olish")
            }

            if subMode == .console {
                terminalConsoleContent
            } else {
                backupCenterContent
            }
        }
    }

    // =========================================================================
    // MARK: - Sub-Mode 1: Interactive In-App Terminal Console
    // =========================================================================

    private var terminalConsoleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Quick Command Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    quickCommandPill(title: "⚡ Bugungi (18-Okt) Sync", cmd: "fc sync-today", tint: Color(red: 0.30, green: 0.66, blue: 1.00))
                    quickCommandPill(title: "📊 Status", cmd: "fc status", tint: Color(red: 0.36, green: 0.86, blue: 0.96))
                    quickCommandPill(title: "🛡 Backup Olish", cmd: "fc backup", tint: Color(red: 0.22, green: 0.84, blue: 0.52))
                    quickCommandPill(title: "🩺 Doctor", cmd: "fc doctor", tint: Color(red: 0.98, green: 0.78, blue: 0.28))
                    quickCommandPill(title: "📦 ZIP Eksport", cmd: "fc export-zip", tint: Color(red: 0.68, green: 0.52, blue: 0.98))
                    quickCommandPill(title: "❓ Help", cmd: "fc help", tint: .white.opacity(0.75))
                    quickCommandPill(title: "🧹 Clear", cmd: "clear", tint: .white.opacity(0.55))
                }
            }
            .frame(height: 24)

            // Working Directory & History Controls Bar
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 0.36, green: 0.86, blue: 0.96))

                Text(terminal.abbreviatedCwd)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.68))
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button("📂 ~/.focus_corner (Ma'lumotlar bazasi)") {
                        terminal.setWorkingDirectory("~/.focus_corner")
                    }
                    Button("📂 ~/Downloads/FocusCorner (Ilova manbasi)") {
                        terminal.setWorkingDirectory("~/Downloads/FocusCorner")
                    }
                    Button("📂 ~/Downloads") {
                        terminal.setWorkingDirectory("~/Downloads")
                    }
                    Button("📂 ~ (Home)") {
                        terminal.setWorkingDirectory("~")
                    }
                } label: {
                    Text("Papka ▾")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button(action: {
                    isMultiLineMode.toggle()
                }) {
                    Text(isMultiLineMode ? "1-Qator" : "Ko'p qator")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(isMultiLineMode ? .cyan : .white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Ko'p qatorli skript kiritish rejimini yoqish/o'chirish")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            // Terminal Output ScrollView
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(terminal.entries) { entry in
                            terminalEntryCard(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: terminal.entries.count) { _, _ in
                    if let lastId = terminal.entries.last?.id {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Command Input Bar (Single-line or Multi-line)
            HStack(alignment: .center, spacing: 7) {
                Text("$")
                    .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.22, green: 0.84, blue: 0.52))

                if isMultiLineMode {
                    TextEditor(text: $commandInput)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 58)
                        .focused($isCommandFocused)
                } else {
                    TextField("Buyruq yozing (masalan: fc status, fc sync-today, python3 ...)...", text: $commandInput, onCommit: submitCommand)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.white)
                        .focused($isCommandFocused)
                }

                // History Up/Down buttons
                HStack(spacing: 3) {
                    Button(action: {
                        commandInput = terminal.previousHistoryCommand(currentInput: commandInput)
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Oldingi buyruq")

                    Button(action: {
                        commandInput = terminal.nextHistoryCommand()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Keyingi buyruq")
                }

                if terminal.isRunningCommand {
                    Button(action: { terminal.stopRunningCommand() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Stop")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.26))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: submitCommand) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Run")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.25))
                        .foregroundColor(Color(red: 0.45, green: 0.78, blue: 1.00))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCommandFocused ? Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                windowController.notesPanel?.focusForTextInput()
                isCommandFocused = true
            }
        }
    }

    private func quickCommandPill(title: String, cmd: String, tint: Color) -> some View {
        Button(action: {
            terminal.executeCommand(cmd)
        }) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(tint.opacity(0.14))
                .foregroundColor(tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func terminalEntryCard(_ entry: TerminalLogEntry) -> some View {
        let isSuccess = (entry.exitCode == 0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("$ \(entry.command)")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.42, green: 0.78, blue: 1.00))
                    .lineLimit(2)

                Spacer()

                Text(isSuccess ? "✓ 0" : "✗ \(entry.exitCode)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isSuccess ? Color(red: 0.22, green: 0.84, blue: 0.52) : Color(red: 0.96, green: 0.40, blue: 0.44))

                Text("\(entry.durationMs)ms")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))

                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(entry.output, forType: .string)
                    storage.showToast("📋 Terminal javobi buferga nusxalandi")
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Chiqish matnini nusxalash")
            }

            Text(entry.output)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func submitCommand() {
        let trimmed = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commandInput = ""
        terminal.executeCommand(trimmed)
        isCommandFocused = true
    }

    // =========================================================================
    // MARK: - Sub-Mode 2: Comprehensive Backup & Recovery Visual Center
    // =========================================================================

    private var backupCenterContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Protection Summary Card
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.84, blue: 0.52))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Har Tomonlama Ma'lumotlar Himoyasi Faol")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                        Text("Oxirgi zahira: \(backup.lastBackupTimestamp) • Jami: \(backup.snapshots.count) ta snapshot")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer()
                }

                HStack(spacing: 6) {
                    Button(action: {
                        _ = backup.createSnapshot(reason: "Qo'lda (Manual)", silent: false)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.fill")
                            Text("Yangi Snapshot")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.22, green: 0.84, blue: 0.52).opacity(0.20))
                        .foregroundColor(Color(red: 0.28, green: 0.90, blue: 0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        _ = backup.exportFullBackupZipToDownloads()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox.fill")
                            Text("ZIP Eksport")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.20))
                        .foregroundColor(Color(red: 0.45, green: 0.78, blue: 1.00))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        let report = backup.runSystemDoctorAudit()
                        terminal.executeCommand("fc doctor")
                        subMode = .console
                        _ = report
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stethoscope")
                            Text("Diagnostika")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.18))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Snapshots List
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(backup.snapshots) { snap in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(snap.reason)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.92))
                                    Text("\(snap.sizeKB) KB")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundColor(.white.opacity(0.65))
                                        .clipShape(Capsule())
                                }
                                Text("\(snap.createdAt) • SAT: \(snap.satScore) • Vazifalar: \(snap.totalTasksCount) ta")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                            }

                            Spacer()

                            Button(action: {
                                _ = backup.restoreSnapshot(snap)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Tiklash")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.18))
                                .foregroundColor(Color(red: 0.45, green: 0.78, blue: 1.00))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Ushbu nuqtaga barcha vazifa, ball va bloknotni qayta tiklash")

                            Button(action: {
                                let url = backup.backupsDirURL.appendingPathComponent(snap.folderName)
                                NSWorkspace.shared.open(url)
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 22, height: 22)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Finder'da ochish")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}
