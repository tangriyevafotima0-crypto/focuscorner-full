import Foundation
import AppKit
import Combine

public struct TerminalLogEntry: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: String
    public let command: String
    public let output: String
    public let exitCode: Int32
    public let durationMs: Int

    public init(
        id: UUID = UUID(),
        timestamp: String = TerminalLogEntry.currentShortTime(),
        command: String,
        output: String,
        exitCode: Int32 = 0,
        durationMs: Int = 1
    ) {
        self.id = id
        self.timestamp = timestamp
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.durationMs = durationMs
    }

    public static func currentShortTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}

@MainActor
public final class TerminalManager: ObservableObject {
    public static let shared = TerminalManager()

    @Published public var entries: [TerminalLogEntry] = []
    @Published public var currentWorkingDirectory: String
    @Published public var isRunningCommand: Bool = false
    @Published public var commandHistory: [String] = []
    @Published public var historyCursor: Int = -1

    private var activeProcess: Process?
    private let maxEntriesCap: Int = 80
    private let maxOutputCharsCap: Int = 24000

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fcDir = "\(home)/.focus_corner"
        self.currentWorkingDirectory = FileManager.default.fileExists(atPath: fcDir) ? fcDir : home

        entries.append(
            TerminalLogEntry(
                command: "fc status",
                output: """
                🚀 FocusCorner v6.5 Ichki Terminal, RPA (No-Error 20%) & Backup Konsoliga Xush Kelibsiz!
                • Ichki buyruqlar: `fc status`, `fc rpa`, `fc rpa x <1..3> [kecha|bugun|ertaga]`, `fc sync-today`, `fc backup`, `fc backups`, `fc restore`, `fc doctor`, `fc add "..."`, `fc done <n>`, `clear`, `help`
                • Tashqi macOS Zsh / Python3 / GuCTL komandalarni ham to'g'ridan-to'g'ri yozishingiz yoki "📋 Paste & Run" tugmasi orqali buferdan ishga tushirishingiz mumkin.
                """,
                exitCode: 0,
                durationMs: 1
            )
        )
    }

    public var abbreviatedCwd: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if currentWorkingDirectory.hasPrefix(home) {
            let rel = String(currentWorkingDirectory.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~\(rel)"
        }
        return currentWorkingDirectory
    }

    public func setWorkingDirectory(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            currentWorkingDirectory = URL(fileURLWithPath: expanded).standardizedFileURL.path
        } else {
            appendEntry(command: "cd \(path)", output: "❌ Papka topilmadi: \(expanded)", exitCode: 1, durationMs: 1)
        }
    }

    public func runClipboardCommandImmediately() {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else {
            StorageManager.shared.showToast("📋 Buferda (Clipboard) matn topilmadi")
            return
        }
        executeCommand(clip)
    }

    public func stopRunningCommand() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
        }
        activeProcess = nil
        isRunningCommand = false
        appendEntry(command: "^C (To'xtatildi)", output: "⏹ Jarayon foydalanuvchi to'monidan to'xtatildi.", exitCode: 130, durationMs: 0)
    }

    public func clearConsole() {
        entries.removeAll()
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func previousHistoryCommand(currentInput: String) -> String {
        guard !commandHistory.isEmpty else { return currentInput }
        if historyCursor < 0 {
            historyCursor = commandHistory.count - 1
        } else if historyCursor > 0 {
            historyCursor -= 1
        }
        return commandHistory[historyCursor]
    }

    public func nextHistoryCommand() -> String {
        guard !commandHistory.isEmpty, historyCursor >= 0 else { return "" }
        if historyCursor < commandHistory.count - 1 {
            historyCursor += 1
            return commandHistory[historyCursor]
        } else {
            historyCursor = -1
            return ""
        }
    }

    // MARK: - Command Dispatcher (Built-in `fc` + Real `/bin/zsh`)

    public func executeCommand(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
            if commandHistory.count > 60 {
                commandHistory.removeFirst()
            }
        }
        historyCursor = -1

        if !trimmed.contains("\n") {
            if trimmed == "clear" || trimmed == "cls" || trimmed == "fc clear" {
                clearConsole()
                return
            }
            if trimmed == "help" || trimmed == "fc help" || trimmed == "fc --help" {
                appendEntry(command: trimmed, output: builtInHelpText(), exitCode: 0, durationMs: 1)
                return
            }
            if trimmed == "status" || trimmed == "fc status" {
                let out = BackupManager.shared.runSystemDoctorAudit()
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 2)
                return
            }
            if trimmed == "rpa" || trimmed == "fc rpa" || trimmed.hasPrefix("fc rpa ") {
                let out = handleBuiltInRPACommand(trimmed)
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 2)
                return
            }
            if trimmed == "sync-today" || trimmed == "fc sync-today" {
                let out = StorageManager.shared.syncTodayScheduleAndScores(force: true)
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 4)
                return
            }
            if trimmed == "backup" || trimmed == "fc backup" || trimmed.hasPrefix("fc backup ") {
                let label = trimmed.replacingOccurrences(of: "fc backup", with: "")
                    .replacingOccurrences(of: "backup", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let reason = label.isEmpty ? "Terminal CLI Backup" : label
                if let snap = BackupManager.shared.createSnapshot(reason: reason, silent: false) {
                    let msg = "✅ Zahira nusxa yaratildi!\n• Papka: ~/.focus_corner/backups/\(snap.folderName)\n• Hajmi: \(snap.sizeKB) KB | SAT: \(snap.satScore) | Vazifalar: \(snap.totalTasksCount) ta"
                    appendEntry(command: trimmed, output: msg, exitCode: 0, durationMs: 8)
                } else {
                    appendEntry(command: trimmed, output: "❌ Zahira yaratishda xatolik yuz berdi.", exitCode: 1, durationMs: 5)
                }
                return
            }
            if trimmed == "backups" || trimmed == "fc backups" {
                BackupManager.shared.refreshSnapshotsList()
                let list = BackupManager.shared.snapshots
                if list.isEmpty {
                    appendEntry(command: trimmed, output: "Hozircha zahira nusxalar yo'q. `fc backup` deb yozing.", exitCode: 0, durationMs: 1)
                } else {
                    var lines = ["🛡 Mavjud Zahira Nusxalar (\(list.count) ta):"]
                    for (idx, s) in list.prefix(15).enumerated() {
                        lines.append("  [\(idx + 1)] \(s.folderName) • \(s.createdAt) • \(s.reason) (SAT: \(s.satScore), Vazifa: \(s.totalTasksCount) ta, \(s.sizeKB) KB)")
                    }
                    appendEntry(command: trimmed, output: lines.joined(separator: "\n"), exitCode: 0, durationMs: 2)
                }
                return
            }
            if trimmed == "restore" || trimmed == "fc restore" || trimmed == "fc restore latest" {
                BackupManager.shared.refreshSnapshotsList()
                guard let latest = BackupManager.shared.snapshots.first else {
                    appendEntry(command: trimmed, output: "❌ Tiklash uchun zahira topilmadi.", exitCode: 1, durationMs: 1)
                    return
                }
                let ok = BackupManager.shared.restoreSnapshot(latest)
                appendEntry(
                    command: trimmed,
                    output: ok ? "♻️ Eng so'nggi zahiradan (\(latest.folderName)) muvaffaqiyatli tiklandi!" : "❌ Tiklashda xatolik.",
                    exitCode: ok ? 0 : 1,
                    durationMs: 10
                )
                return
            }
            if trimmed == "export-zip" || trimmed == "fc export-zip" {
                let path = BackupManager.shared.exportFullBackupZipToDownloads()
                appendEntry(
                    command: trimmed,
                    output: path.isEmpty ? "❌ ZIP eksportda xatolik." : "📦 To'liq ZIP zahira saqlandi: \(path)",
                    exitCode: path.isEmpty ? 1 : 0,
                    durationMs: 25
                )
                return
            }
            if trimmed == "doctor" || trimmed == "fc doctor" {
                let out = BackupManager.shared.runSystemDoctorAudit()
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 4)
                return
            }
            if trimmed.hasPrefix("fc add ") {
                let rest = String(trimmed.dropFirst("fc add ".count)).trimmingCharacters(in: .whitespaces)
                let out = handleBuiltInAddTask(rest)
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 2)
                return
            }
            if trimmed.hasPrefix("fc done ") {
                let query = String(trimmed.dropFirst("fc done ".count)).trimmingCharacters(in: .whitespaces)
                let out = handleBuiltInDoneTask(query)
                appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 2)
                return
            }
            if trimmed.hasPrefix("fc sat ") {
                let parts = trimmed.split(separator: " ").map(String.init)
                if parts.count >= 4, let m = Int(parts[2]), let rw = Int(parts[3]) {
                    let out = StorageManager.shared.setExplicitSATScores(math: m, rw: rw)
                    appendEntry(command: trimmed, output: out, exitCode: 0, durationMs: 3)
                    return
                }
            }
            if trimmed.hasPrefix("fc exacc ") {
                let parts = trimmed.split(separator: " ").map(String.init)
                if parts.count >= 3, let val = Double(parts[2]) {
                    StorageManager.shared.exAcc.totalStandardCharge = max(0, val)
                    StorageManager.shared.saveExAcc()
                    appendEntry(command: trimmed, output: "⚡ ExAcc Standart Zaryad yangilandi: \(Int(val)) ball", exitCode: 0, durationMs: 2)
                    return
                }
            }
            if trimmed == "cd" || trimmed.hasPrefix("cd ") {
                let target = trimmed == "cd" ? "~" : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                setWorkingDirectory(target)
                appendEntry(command: trimmed, output: "📂 Ishchi papka: \(currentWorkingDirectory)", exitCode: 0, durationMs: 1)
                return
            }
        }

        runShellCommandAsync(trimmed)
    }

    private func handleBuiltInRPACommand(_ raw: String) -> String {
        let storage = StorageManager.shared
        let parts = raw.split(separator: " ").map(String.init)
        if parts.count >= 4 && parts[1].lowercased() == "rpa" && parts[2].lowercased() == "x" {
            if let idx = Int(parts[3]), idx >= 1, idx <= storage.rules.count {
                let rule = storage.rules[idx - 1]
                let dayArg = parts.count >= 5 ? parts[4].lowercased() : "bugun"
                let targetDate: String
                if dayArg == "kecha" {
                    targetDate = storage.rpaYesterdayString
                } else if dayArg == "ertaga" {
                    targetDate = storage.rpaTomorrowString
                } else {
                    targetDate = storage.rpaTodayString
                }
                storage.toggleRPAMarkX(rule, on: targetDate)
                let isNowX = storage.rules[idx - 1].isMarkedX(on: targetDate)
                return "🛡 RPA yangilandi (\(targetDate)): \(rule.title) -> \(isNowX ? "[ X ]" : "[ — ]") • Gu No-Error: \(storage.currentGuNoErrorScore)/20%"
            }
        }

        let cols = storage.rpaThreeDayColumns
        var lines: [String] = [
            "=== 🛡 FocusCorner RPA (3-Kunlik Anti-Odat & Gu No-Error 20% Sektori) ===",
            "• Gu No-Error Sektori: \(storage.currentGuNoErrorScore) / 20% (Bugun: \(storage.todayRPAXCount) ta X | Kecha: \(storage.yesterdayRPAXCount) ta X)",
            "• Sanalar: \(cols[0].title)(\(cols[0].shortDate)) | \(cols[1].title)(\(cols[1].shortDate)) | \(cols[2].title)(\(cols[2].shortDate))",
            "------------------------------------------------------------------------"
        ]
        for (i, r) in storage.rules.enumerated() {
            let c0 = r.isMarkedX(on: cols[0].dateString) ? "[X]" : "[—]"
            let c1 = r.isMarkedX(on: cols[1].dateString) ? "[X]" : "[—]"
            let c2 = r.isMarkedX(on: cols[2].dateString) ? "[X]" : "[—]"
            lines.append("  [\(i + 1)] \(c0) \(c1) \(c2)  \(r.title)")
        }
        lines.append("• Belgilash uchun: `fc rpa x 1 bugun` yoki `fc rpa x 2 kecha`")
        return lines.joined(separator: "\n")
    }

    private func handleBuiltInAddTask(_ rawArgs: String) -> String {
        var days = 1
        var src: TaskSourceSystem = .general
        var clean = rawArgs
        if clean.contains("--sat") {
            src = .sat
            clean = clean.replacingOccurrences(of: "--sat", with: "")
        }
        if clean.contains("--exacc") {
            src = .exacc
            clean = clean.replacingOccurrences(of: "--exacc", with: "")
        }
        if let range = clean.range(of: #"--days\s+(\d+)"#, options: .regularExpression) {
            let sub = String(clean[range])
            let digits = sub.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let d = Int(digits) { days = max(1, min(90, d)) }
            clean.removeSubrange(range)
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        guard !clean.isEmpty else {
            return "⚠️ Vazifa nomini kiriting. Masalan: fc add \"Quadratic Functions\" --days 1 --sat"
        }
        StorageManager.shared.addTask(title: clean, source: src, durationDays: days)
        return "✅ Vazifa qo'shildi (\(days == 1 ? "Bugun • Ko'k" : "\(days) kun")): \(clean)"
    }

    private func handleBuiltInDoneTask(_ query: String) -> String {
        let storage = StorageManager.shared
        let active = storage.tasks.filter { !$0.isCompleted }
        if let idx = Int(query), idx >= 1, idx <= active.count {
            let target = active[idx - 1]
            storage.toggleTask(target)
            return "🟢 Bajarildi deb belgilandi: \(target.title)"
        }
        if let match = active.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
            storage.toggleTask(match)
            return "🟢 Bajarildi deb belgilandi: \(match.title)"
        }
        return "⚠️ '\(query)' bo'yicha faol vazifa topilmadi."
    }

    private func builtInHelpText() -> String {
        return """
        === 🛠 FocusCorner v6.5 Ichki Terminal Buyruqlari ===
        • fc status                       — SAT, ExAcc, RPA (Gu No-Error 20%), Vazifalar va Backup holati
        • fc rpa                          — 3-kunlik RPA (Kecha, Bugun, Ertaga) jadvalini ko'rish
        • fc rpa x <raqam> [bugun|kecha]  — RPA odatiga [X] belgisini qo'yish yoki olib tashlash
        • fc sync-today                   — 22-Oktabr jadvali, 791 SAT va 230 ExAcc ni sinxronlash
        • fc add "Nomi" --days 1          — Yangi vazifa qo'shish (--sat yoki --exacc bayrog'i bilan)
        • fc done <raqam yoki so'z>       — Vazifani bajarildi (Yashil) deb belgilash
        • fc sat <math> <rw>              — SAT ballarini bevosita o'rnatish (masalan: fc sat 345 446)
        • fc exacc <ball>                 — ExAcc zaryadini o'rnatish (masalan: fc exacc 230)
        • fc backup [izoh]                — Barcha fayllar va bloknotdan tezkor Snapshot zahira olish
        • fc backups                      — Barcha saqlangan zahira nusxalar ro'yxati
        • fc restore                      — Eng so'nggi zahira nusxadan 1 bosishda qayta tiklash
        • fc export-zip                   — ~/Downloads papkasiga to'liq ZIP arxiv eksport qilish
        • fc doctor                       — Fayllar butunligi va tizim diagnostikasini o'tkazish
        • clear                           — Terminal ekranini tozalash
        """
    }

    private func runShellCommandAsync(_ command: String) {
        if isRunningCommand {
            stopRunningCommand()
        }

        if command.contains("tasks.json") || command.contains("sat_tracker.json") || command.contains(".focus_corner") {
            BackupManager.shared.createAutoBackupIfNeeded(reason: "Terminal Skript Oldidan")
        }

        isRunningCommand = true
        let startTime = Date()
        let cwd = currentWorkingDirectory

        let proc = Process()
        let outPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = "\(extraPath):\(existingPath)"
        } else {
            env["PATH"] = extraPath
        }
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["PYTHONIOENCODING"] = "utf-8"
        proc.environment = env

        proc.standardOutput = outPipe
        proc.standardError = outPipe

        do {
            try proc.run()
            self.activeProcess = proc
        } catch {
            let errMsg = "❌ Ishga tushirib bo'lmadi: \(error.localizedDescription)"
            self.isRunningCommand = false
            self.activeProcess = nil
            self.appendEntry(command: command, output: errMsg, exitCode: 127, durationMs: 1)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            let elapsedMs = max(1, Int(Date().timeIntervalSince(startTime) * 1000.0))
            let status = proc.terminationStatus
            var combined = (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty {
                combined = status == 0 ? "✓ Buyruq muvaffaqiyatli bajarildi (chiqish matni yo'q)." : "⚠️ Jarayon \(status) kodi bilan yakunlandi."
            }
            if combined.count > 24000 {
                combined = String(combined.prefix(24000)) + "\n... [Chiqish matni RAM tejash uchun qisqartirildi]"
            }

            Task { @MainActor in
                guard let self = self else { return }
                self.isRunningCommand = false
                self.activeProcess = nil
                self.appendEntry(command: command, output: combined, exitCode: status, durationMs: elapsedMs)
                StorageManager.shared.reloadFromDiskSafely()
                BackupManager.shared.refreshSnapshotsList()
                DevChannelManager.shared.silentMemoryTrim()
            }
        }
    }

    private func appendEntry(command: String, output: String, exitCode: Int32, durationMs: Int) {
        let item = TerminalLogEntry(
            command: command,
            output: output,
            exitCode: exitCode,
            durationMs: durationMs
        )
        entries.append(item)
        if entries.count > maxEntriesCap {
            entries.removeFirst(entries.count - maxEntriesCap)
        }
    }
}
