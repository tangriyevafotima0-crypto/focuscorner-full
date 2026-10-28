import Foundation
import AppKit
import Combine

@MainActor
public final class FocusTimerManager: ObservableObject {
    public static let shared = FocusTimerManager()

    @Published public var config: TimerConfiguration = TimerConfiguration()
    @Published public var isActive: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var isCompactPill: Bool = false
    @Published public var currentPartIndex: Int = 0
    @Published public var remainingSeconds: Int = 2700
    @Published public var totalPartSeconds: Int = 2700
    @Published public var activeTaskId: UUID? = nil
    @Published public var activeSessionTitle: String = ""
    @Published public var rpaRuleTickerIndex: Int = 0

    private let configFileURL: URL
    private var tickTimer: Timer?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.configFileURL = baseDir.appendingPathComponent("timer_config.json")
        loadConfig()
    }

    public func loadConfig() {
        if let data = try? Data(contentsOf: configFileURL),
           let loaded = try? JSONDecoder().decode(TimerConfiguration.self, from: data) {
            self.config = loaded
        } else {
            self.config = TimerConfiguration()
            saveConfig()
        }
        resetPreviewRemaining()
    }

    public func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFileURL, options: .atomic)
        }
    }

    private func resetPreviewRemaining() {
        guard !isActive else { return }
        if config.mode == .singular {
            let secs = max(1, config.singularMinutes) * 60
            self.totalPartSeconds = secs
            self.remainingSeconds = secs
        } else if let first = config.examParts.first {
            let secs = max(1, first.durationMinutes) * 60
            self.totalPartSeconds = secs
            self.remainingSeconds = secs
        }
    }

    // MARK: - Current Part Info

    public var currentPart: TimerPart? {
        guard config.mode == .exam,
              currentPartIndex >= 0,
              currentPartIndex < config.examParts.count else { return nil }
        return config.examParts[currentPartIndex]
    }

    public var isBreakPhase: Bool {
        if config.mode == .exam, let part = currentPart {
            return part.kind == .rest
        }
        return false
    }

    public var currentHeaderBadge: String {
        if config.mode == .singular {
            return "⏱ SINGULAR FOKUS"
        } else {
            let total = max(1, config.examParts.count)
            let idx = min(total, currentPartIndex + 1)
            let kindLabel = isBreakPhase ? "☕ DAM OLISH" : "🎯 ISH / FOKUS"
            return "EXAM \(idx)/\(total) • \(kindLabel)"
        }
    }

    public var currentDisplaySubtitle: String {
        if config.mode == .exam, let part = currentPart {
            if !activeSessionTitle.isEmpty {
                return "\(part.title) • \(activeSessionTitle)"
            }
            return part.title
        }
        if !activeSessionTitle.isEmpty {
            return activeSessionTitle
        }
        return "Chalg'ituvchi narsalar o'chirilgan — Chuqur Fokus"
    }

    public var progressFraction: Double {
        guard totalPartSeconds > 0 else { return 0 }
        let elapsed = Double(totalPartSeconds - remainingSeconds)
        return max(0.0, min(1.0, elapsed / Double(totalPartSeconds)))
    }

    public var formattedTime: String {
        let hrs = remainingSeconds / 3600
        let mins = (remainingSeconds % 3600) / 60
        let secs = remainingSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    public var activeRPAReminderText: String {
        let rules = StorageManager.shared.rules
        guard !rules.isEmpty else {
            return "🛡 Fokus vaqtida telefon va ijtimoiy tarmoq taqiqlanadi"
        }
        let idx = abs(rpaRuleTickerIndex) % rules.count
        return "🛡 \(rules[idx].title)"
    }

    public func cycleRPAReminder() {
        rpaRuleTickerIndex += 1
    }

    // MARK: - Start / Control Timer

    public func startSingular(minutes: Int? = nil, linkedTask: TaskItem? = nil) {
        if let m = minutes {
            config.singularMinutes = max(1, min(300, m))
        }
        config.mode = .singular
        saveConfig()

        let secs = config.singularMinutes * 60
        self.totalPartSeconds = secs
        self.remainingSeconds = secs
        self.currentPartIndex = 0
        self.activeTaskId = linkedTask?.id
        self.activeSessionTitle = linkedTask?.title ?? "Singular Fokus (\(config.singularMinutes) daqiqa)"
        self.isPaused = false
        self.isActive = true

        NSSound(named: "Tink")?.play()
        startTicker()
        WindowController.shared.enterZenTimerMode()
    }

    public func startExam(parts: [TimerPart]? = nil, linkedTask: TaskItem? = nil) {
        if let p = parts, !p.isEmpty {
            config.examParts = p
        }
        if config.examParts.isEmpty {
            config.examParts = ExamTemplatePreset.classic60_10_45.parts
        }
        config.mode = .exam
        saveConfig()

        self.currentPartIndex = 0
        let first = config.examParts[0]
        let secs = max(1, first.durationMinutes) * 60
        self.totalPartSeconds = secs
        self.remainingSeconds = secs
        self.activeTaskId = linkedTask?.id
        self.activeSessionTitle = linkedTask?.title ?? ""
        self.isPaused = false
        self.isActive = true

        NSSound(named: "Tink")?.play()
        startTicker()
        WindowController.shared.enterZenTimerMode()
    }

    public func startQuickTimerForTask(_ task: TaskItem) {
        let defaultMins: Int
        if task.sourceSystem == .sat && task.satStage == .ingest {
            defaultMins = 45
        } else if task.accumulatorSize == .big {
            defaultMins = 60
        } else if task.accumulatorSize == .medium {
            defaultMins = 45
        } else {
            defaultMins = 25
        }
        startSingular(minutes: defaultMins, linkedTask: task)
    }

    public func togglePause() {
        guard isActive else { return }
        isPaused.toggle()
    }

    public func addMinutes(_ mins: Int) {
        let delta = mins * 60
        remainingSeconds = max(10, remainingSeconds + delta)
        totalPartSeconds = max(totalPartSeconds, remainingSeconds)
    }

    public func restartCurrentPart() {
        if config.mode == .singular {
            let secs = max(1, config.singularMinutes) * 60
            totalPartSeconds = secs
            remainingSeconds = secs
        } else if let part = currentPart {
            let secs = max(1, part.durationMinutes) * 60
            totalPartSeconds = secs
            remainingSeconds = secs
        }
        isPaused = false
    }

    public func skipToNextPart() {
        guard config.mode == .exam else {
            stopTimer(completedNaturally: false)
            return
        }
        advanceToPart(index: currentPartIndex + 1)
    }

    public func previousPart() {
        guard config.mode == .exam, currentPartIndex > 0 else { return }
        advanceToPart(index: currentPartIndex - 1)
    }

    private func advanceToPart(index: Int) {
        guard index >= 0 && index < config.examParts.count else {
            // Exam sequence finished!
            NSSound(named: "Hero")?.play()
            StorageManager.shared.appendHistoryLine("- [x] [{TIMESTAMP}] [EXAM-TIMER] Barcha \(config.examParts.count) ta part muvaffaqiyatli yakunlandi!")
            StorageManager.shared.showToast("🎉 Exam Timer barcha partlari yakunlandi! Barakalla!")
            stopTimer(completedNaturally: true)
            return
        }

        currentPartIndex = index
        let nextPart = config.examParts[index]
        let secs = max(1, nextPart.durationMinutes) * 60
        totalPartSeconds = secs
        remainingSeconds = secs
        isPaused = false
        rpaRuleTickerIndex += 1
        NSSound(named: "Glass")?.play()
    }

    public func stopTimer(completedNaturally: Bool = false, markLinkedTaskDone: Bool = false) {
        tickTimer?.invalidate()
        tickTimer = nil

        if markLinkedTaskDone, let tid = activeTaskId,
           let task = StorageManager.shared.tasks.first(where: { $0.id == tid && !$0.isCompleted }) {
            StorageManager.shared.toggleTask(task)
        } else if completedNaturally && config.mode == .singular {
            NSSound(named: "Glass")?.play()
            StorageManager.shared.appendHistoryLine("- [x] [{TIMESTAMP}] [TIMER] Singular Fokus (\(config.singularMinutes)m) yakunlandi: \(activeSessionTitle)")
            StorageManager.shared.showToast("⏰ Fokus vaqti (\(config.singularMinutes) daqiqa) yakunlandi!")
        }

        isActive = false
        isPaused = false
        WindowController.shared.exitZenTimerMode()
    }

    // MARK: - Exam Part Editing Helpers

    public func applyExamPreset(_ preset: ExamTemplatePreset) {
        config.examParts = preset.parts
        config.mode = .exam
        saveConfig()
        resetPreviewRemaining()
    }

    public func addExamPart(title: String = "", minutes: Int = 30, kind: TimerPartKind = .work) {
        let nextNum = config.examParts.count + 1
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(nextNum)-Part: \(kind == .work ? "Fokus Ish" : "Dam olish")"
            : title
        config.examParts.append(TimerPart(title: resolvedTitle, durationMinutes: minutes, kind: kind))
        saveConfig()
    }

    public func removeExamPart(id: UUID) {
        guard config.examParts.count > 1 else { return }
        config.examParts.removeAll { $0.id == id }
        saveConfig()
    }

    public func updateExamPart(id: UUID, title: String? = nil, minutes: Int? = nil, kind: TimerPartKind? = nil) {
        guard let idx = config.examParts.firstIndex(where: { $0.id == id }) else { return }
        if let t = title { config.examParts[idx].title = t }
        if let m = minutes { config.examParts[idx].durationMinutes = max(1, min(300, m)) }
        if let k = kind { config.examParts[idx].kind = k }
        saveConfig()
    }

    // MARK: - Internal Second Ticker

    private func startTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isActive, !self.isPaused else { return }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                    if self.remainingSeconds % 45 == 0 {
                        self.rpaRuleTickerIndex += 1
                    }
                } else {
                    if self.config.mode == .exam {
                        if self.config.autoAdvanceExamParts {
                            self.advanceToPart(index: self.currentPartIndex + 1)
                        } else {
                            self.remainingSeconds = 0
                            self.isPaused = true
                            NSSound(named: "Glass")?.play()
                        }
                    } else {
                        self.stopTimer(completedNaturally: true)
                    }
                }
            }
        }
    }
}
