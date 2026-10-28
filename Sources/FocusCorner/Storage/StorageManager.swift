import Foundation
import AppKit
import Combine

@MainActor
public final class StorageManager: ObservableObject {
    public static let shared = StorageManager()

    @Published public var rules: [RuleItem] = []
    @Published public var tasks: [TaskItem] = []
    @Published public var satTracker: SATTrackerState = SATTrackerState()
    @Published public var exAcc: ExAccState = ExAccState()
    @Published public var settings: AppSettings = AppSettings()
    @Published public var historyContent: String = ""
    @Published public var statusBannerMessage: String = ""
    @Published public var toastBanner: String? = nil

    public let baseDirURL: URL
    public let backupsDirURL: URL
    public let rulesFileURL: URL
    public let tasksFileURL: URL
    public let satFileURL: URL
    public let exAccFileURL: URL
    public let settingsFileURL: URL
    public let historyFileURL: URL

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var isInternalWriteInProgress: Bool = false
    private var protocolTimer: Timer?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirURL = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.backupsDirURL = baseDirURL.appendingPathComponent("backups", isDirectory: true)
        self.rulesFileURL = baseDirURL.appendingPathComponent("rules.json")
        self.tasksFileURL = baseDirURL.appendingPathComponent("tasks.json")
        self.satFileURL = baseDirURL.appendingPathComponent("sat_tracker.json")
        self.exAccFileURL = baseDirURL.appendingPathComponent("exacc.json")
        self.settingsFileURL = baseDirURL.appendingPathComponent("settings.json")
        self.historyFileURL = baseDirURL.appendingPathComponent("history.md")

        ensureDirectoriesAndBackups()
        loadAllData()
        migrateToV3_1BlueSpectrumIfNeeded()
        refreshSafetyProtocolStatus()
        startDirectoryWatcher()
        startSafetyProtocolTimer()
    }

    private func ensureDirectoriesAndBackups() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupsDirURL, withIntermediateDirectories: true)

        if fm.fileExists(atPath: historyFileURL.path) {
            let today = TaskItem.todayString()
            let backupHistoryURL = backupsDirURL.appendingPathComponent("history_backup_\(today).md")
            if !fm.fileExists(atPath: backupHistoryURL.path) {
                try? fm.copyItem(at: historyFileURL, to: backupHistoryURL)
            }
        } else {
            let header = """
            # FocusCorner — Doimiy Bajarilgan Ishlar va Synergy Tarixi (history.md)
            > Ushbu fayl avtomatik to'ldirib boriladi va yangilanishlar paytida hech qachon o'chirilmaydi.

            - [x] [2026-10-10 20:42] [SAT] [Ingest 30%] Linear Functions & Systems (+24 ball)
            - [x] [2026-10-11 14:17] [SAT] [Ingest 30%] Transitions (Logical Connectors) (+21 ball)
            - [x] [2026-10-11 22:36] [SAT] [Day 1 +20%] Linear Functions — Day 1 Review (+16 ball)
            - [x] [2026-10-12 19:46] [SAT] [Day 1 +20%] Transitions — Day 1 Review (+14 ball)
            - [x] [2026-10-12 19:46] [SAT] [Ingest 30%] Subject-Verb Agreement & Pronouns (+12 ball)
            - [x] [2026-10-14 11:48] [SAT] [Ingest 30%] Ratios, Rates, Percentages & Unit Conversions (+15 ball)
            - [x] [2026-10-14 21:19] [SAT] [Day 3 +20%] Transitions — Day 3 Recall (+14 ball)
            - [x] [2026-10-14 21:19] [SAT] [Day 1 +20%] Subject-Verb Agreement — Day 1 Review (+8 ball)
            - [x] [2026-10-14 21:26] [SAT] [Day 1 +20%] Ratios, Rates & Percentages — Day 1 Review (+8 ball)
            - [x] [2026-10-14 22:28] [SAT] [Day 3 +20%] Linear Functions — Day 3 Recall (+16 ball)
            - [x] [2026-10-16 09:05] [SAT] [Day 3 +20%] Subject-Verb Agreement & Pronouns — Day 3 Recall (+8 ball)

            """
            try? header.write(to: historyFileURL, atomically: true, encoding: .utf8)
        }
    }

    public func loadAllData() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: settingsFileURL),
           var loaded = try? decoder.decode(AppSettings.self, from: data) {
            loaded.isGhostClickThrough = false
            loaded.isRulesPinned = false
            if loaded.rulesOpacity < 0.85 { loaded.rulesOpacity = 0.96 }
            if loaded.notesOpacity < 0.85 { loaded.notesOpacity = 0.96 }
            self.settings = loaded
            saveSettings()
        } else {
            self.settings = AppSettings()
            saveSettings()
        }

        if let data = try? Data(contentsOf: rulesFileURL),
           let loaded = try? decoder.decode([RuleItem].self, from: data),
           !loaded.isEmpty {
            self.rules = loaded
        } else {
            self.rules = RuleItem.defaultRPARules
            saveRules()
        }

        if let data = try? Data(contentsOf: satFileURL),
           let loaded = try? decoder.decode(SATTrackerState.self, from: data) {
            self.satTracker = loaded
        } else {
            self.satTracker = SATTrackerState()
            saveSATTracker()
        }

        if let data = try? Data(contentsOf: exAccFileURL),
           let loaded = try? decoder.decode(ExAccState.self, from: data) {
            self.exAcc = loaded
            syncSATFactionObserverMission()
        } else {
            self.exAcc = ExAccState()
            syncSATFactionObserverMission()
            saveExAcc()
        }

        if let data = try? Data(contentsOf: tasksFileURL),
           let loaded = try? decoder.decode([TaskItem].self, from: data) {
            self.tasks = loaded
        } else {
            self.tasks = []
            saveTasks()
        }

        if let hist = try? String(contentsOf: historyFileURL, encoding: .utf8) {
            self.historyContent = hist
        }
    }

    /// Automatically syncs the Oct 16, 2026 schedule and applies the 5-stage Blue-Spectrum durations:
    /// - Bugun (1 kun) -> Ochiqroq ko'k ("Bugun • Ko'k")
    /// - 3 kun qolganda -> Havorang ("3 kun qoldi • Havorang")
    /// - 4+ kun qolganda -> Ko'kish oq ("7 kun qoldi • Ko'kish oq")
    /// - 1 kun o'tib ketganda -> Qizil ("1 kun o'tib ketdi • Qizil")
    /// - Bajarilganda -> Yashil ("Bajarildi • Yashil")
    private func migrateToV3_1BlueSpectrumIfNeeded() {
        guard !settings.migratedV3_1BlueSpectrum else { return }
        let today = TaskItem.todayString()

        // 1. Ensure Subject-Verb Agreement Day 3 is marked completed (+8 -> 28/40 -> 556 SAT)
        if let idx = satTracker.topics.firstIndex(where: { $0.title.lowercased().contains("subject-verb") }) {
            if satTracker.topics[idx].currentScore < 28 {
                satTracker.topics[idx].currentScore = 28
                satTracker.topics[idx].status = .refined70
            }
            if let cpIdx = satTracker.topics[idx].checkpoints.firstIndex(where: { $0.stage == .day3 }) {
                satTracker.topics[idx].checkpoints[cpIdx].isCompleted = true
                satTracker.topics[idx].checkpoints[cpIdx].completedDate = "2026-10-16"
            }
            saveSATTracker()
        }

        if exAcc.totalStandardCharge < 145 {
            exAcc.totalStandardCharge = 145
            saveExAcc()
        }

        // Remove stale Oct 14/15 uncompleted tasks or old v3.0 sample tasks so v3.1 spectrum is clean
        tasks.removeAll { item in
            let lower = item.title.lowercased()
            if lower.contains("quadratic") || lower.contains("parabola") || lower.contains("punctuation") || lower.contains("words in context") || lower.contains("ratios") || lower.contains("subject-verb") || lower.contains("haftalik mini-acc") || lower.contains("focuscorner v2.0") {
                return true
            }
            return false
        }

        let seededTasks: [TaskItem] = [
            // 1. Bugun bajarish kerak (1 kun qoldi -> Ochiqroq ko'k: "Bugun • Ko'k")
            TaskItem(
                title: "[SAT SR] Ratios, Rates, Percentages & Units — Day 3 Recall",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .small,
                satStage: .day3,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 8,
                notes: "Bugun 18:00 da bajariladigan Day 3 takrorlash (+8 ball)"
            ),
            TaskItem(
                title: "[SAT English] Boundaries & Punctuation — Deep Focus (Ingest 30%)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 21,
                notes: "Bugungi asosiy mavzu: Semicolons, Colons, Dashes & Comma Splices"
            ),
            TaskItem(
                title: "[SAT English] Words in Context — Deep Focus (Ingest 30%)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 21,
                notes: "Bugun 18:30: Tone, Charge (+/-) va Context Clues"
            ),
            // 2. 3 kun qolganda (Havorang: "3 kun qoldi • Havorang")
            TaskItem(
                title: "[SAT Math] Quadratic Functions & Parabolas — Sunday Buffer (Ingest 30%)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: "2026-10-18",
                startDate: today,
                durationDays: 3,
                pointsValue: 24,
                notes: "Yakshanba (18-Okt) buffer kuniga belgilangan — 3 kunlik Havorang rejim"
            ),
            // 3. 3 kundan ko'proq (7 kun -> Ko'kish oq: "7 kun qoldi (7k) • Ko'kish oq")
            TaskItem(
                title: "[ExAcc] Haftalik Mini-Acc Deep Work Bloki",
                isCompleted: false,
                sourceSystem: .exacc,
                accumulatorSize: .medium,
                satStage: .none,
                scheduledDate: "2026-10-22",
                startDate: today,
                durationDays: 7,
                pointsValue: 25,
                notes: "3 kundan ko'p qolganda Ko'kish oq rangda turadi"
            ),
            // 4. Bajarilgan vazifa namunasi (Bajarilganda Yashil: "Bajarildi • Yashil")
            TaskItem(
                title: "[SAT SR] Subject-Verb Agreement & Pronouns — Day 3 Recall",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .sat,
                accumulatorSize: .small,
                satStage: .day3,
                scheduledDate: "2026-10-15",
                startDate: "2026-10-15",
                durationDays: 1,
                pointsValue: 8,
                notes: "Bajarildi (+8 ball qo'shildi — SAT 556)"
            )
        ]

        for t in seededTasks.reversed() {
            tasks.insert(t, at: 0)
        }

        // Clean up harsh legacy RPA rules so Eslatmalar feels calm and pleasant
        if rules.contains(where: { $0.title.contains("QAT'IYAN TAQIQLANADI") || $0.title.contains("WIP Limit <=") }) {
            rules = RuleItem.defaultRPARules
            saveRules()
        }
        settings.migratedV3Oct16 = true
        settings.migratedV3_1BlueSpectrum = true
        saveSettings()
        saveTasks()
    }

    public func RPAResetCustomOrigin() {
        settings.rulesOriginX = nil
        settings.rulesOriginY = nil
    }

    // MARK: - Atomic JSON Persistence

    private func atomicWriteJSON<T: Encodable>(_ value: T, to url: URL) {
        isInternalWriteInProgress = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.isInternalWriteInProgress = false
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }

        let tempURL = baseDirURL.appendingPathComponent(".\(url.lastPathComponent).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func saveRules() { atomicWriteJSON(rules, to: rulesFileURL) }
    public func saveTasks() { atomicWriteJSON(tasks, to: tasksFileURL) }
    public func saveSATTracker() {
        atomicWriteJSON(satTracker, to: satFileURL)
        syncSATFactionObserverMission()
    }
    public func saveExAcc() { atomicWriteJSON(exAcc, to: exAccFileURL) }
    public func saveSettings() { atomicWriteJSON(settings, to: settingsFileURL) }

    public func appendHistoryLine(_ line: String) {
        isInternalWriteInProgress = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.isInternalWriteInProgress = false
            }
        }
        let timestamp = Self.formattedTimestamp()
        let entry = "\(line.replacingOccurrences(of: "{TIMESTAMP}", with: timestamp))\n"

        if let handle = try? FileHandle(forWritingTo: historyFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = entry.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            let current = (try? String(contentsOf: historyFileURL, encoding: .utf8)) ?? ""
            try? (current + entry).write(to: historyFileURL, atomically: true, encoding: .utf8)
        }

        if let updated = try? String(contentsOf: historyFileURL, encoding: .utf8) {
            self.historyContent = updated
        }
    }

    private static func formattedTimestamp(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    public func showToast(_ message: String) {
        self.toastBanner = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.toastBanner == message {
                self?.toastBanner = nil
            }
        }
    }

    // MARK: - Rules Management

    public func addRule(title: String, type: RPARuleType, isLocked: Bool = false) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = RuleItem(title: trimmed, ruleType: type, isLocked: isLocked)
        rules.insert(item, at: 0)
        saveRules()
        appendHistoryLine("- [RPA+] [{TIMESTAMP}] [\(type.rawValue)] \(trimmed)")
    }

    public func updateRule(_ rule: RuleItem, newTitle: String, newType: RPARuleType) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx].title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        rules[idx].ruleType = newType
        saveRules()
    }

    public func toggleRuleLock(_ rule: RuleItem) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[idx].isLocked.toggle()
        saveRules()
    }

    public func deleteRule(_ rule: RuleItem) {
        deleteRuleForce(rule)
    }

    public func deleteRuleForce(_ rule: RuleItem) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
        appendHistoryLine("- [RPA-] [{TIMESTAMP}] O'chirildi: \(rule.title)")
    }

    // MARK: - Task & Duration Operations

    public func addTask(
        title: String,
        source: TaskSourceSystem = .general,
        accumulator: AccumulatorSize = .none,
        satStage: SATReviewStage = .none,
        scheduledDate: String? = nil,
        durationDays: Int = 1,
        points: Double? = nil,
        notes: String = ""
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedPoints: Double
        if let pts = points, pts > 0 {
            resolvedPoints = pts
        } else if source == .exacc {
            resolvedPoints = accumulator == .none ? 25 : accumulator.points
        } else if source == .sat {
            resolvedPoints = satStage == .ingest ? 21 : 8
        } else {
            resolvedPoints = 0
        }

        let today = TaskItem.todayString()
        let dueDate = Calendar.current.date(byAdding: .day, value: max(0, durationDays - 1), to: Date()) ?? Date()
        let resolvedScheduled = scheduledDate ?? TaskItem.todayString(from: dueDate)

        let item = TaskItem(
            title: trimmed,
            isCompleted: false,
            sourceSystem: source,
            accumulatorSize: source == .exacc && accumulator == .none ? .medium : accumulator,
            satStage: source == .sat && satStage == .none ? .ingest : satStage,
            scheduledDate: resolvedScheduled,
            startDate: today,
            durationDays: max(1, min(90, durationDays)),
            manualElapsedDaysOffset: 0,
            pointsValue: resolvedPoints,
            notes: notes
        )
        tasks.insert(item, at: 0)
        saveTasks()
    }

    public func setTaskDurationDays(_ task: TaskItem, days: Int) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].startDate = TaskItem.todayString()
        tasks[idx].durationDays = max(1, min(90, days))
        tasks[idx].manualElapsedDaysOffset = 0
        tasks[idx].isCompleted = false
        saveTasks()
    }

    /// Sets task to overdue state (e.g. 1 kun o'tib ketdi -> Qizil) for immediate status control or testing
    public func setTaskOverdueByDays(_ task: TaskItem, overdueDays: Int = 1) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let calDiff = TaskItem.daysBetween(from: tasks[idx].startDate, to: TaskItem.todayString())
        // We want remainingDays = durationDays - (calDiff + manualElapsedDaysOffset) == -(overdueDays - 1)
        let targetRemaining = -(max(1, overdueDays) - 1)
        tasks[idx].manualElapsedDaysOffset = tasks[idx].durationDays - calDiff - targetRemaining
        tasks[idx].isCompleted = false
        saveTasks()
    }

    public func stepTaskElapsedDay(_ task: TaskItem, delta: Int) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newOffset = tasks[idx].manualElapsedDaysOffset + delta
        tasks[idx].manualElapsedDaysOffset = max(-30, min(60, newOffset))
        saveTasks()
    }

    public func toggleTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let willComplete = !tasks[idx].isCompleted

        tasks[idx].isCompleted = willComplete
        tasks[idx].completedAt = willComplete ? Date() : nil
        let updatedTask = tasks[idx]
        saveTasks()

        if willComplete {
            let ptsTag = updatedTask.pointsValue > 0 ? " (+\(formatPoints(updatedTask.pointsValue)) ball)" : ""
            appendHistoryLine("- [x] [{TIMESTAMP}] [\(updatedTask.sourceSystem.rawValue)] \(updatedTask.title)\(ptsTag)")
            applySynergyReward(for: updatedTask, isCompleting: true)
        } else {
            appendHistoryLine("- [ ] [{TIMESTAMP}] [UNDO] \(updatedTask.title)")
            applySynergyReward(for: updatedTask, isCompleting: false)
        }

        refreshSafetyProtocolStatus()
    }

    public func updateTaskTitle(_ task: TaskItem, newTitle: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks[idx].title = trimmed
        saveTasks()
    }

    public func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
        appendHistoryLine("- [-] [{TIMESTAMP}] [DELETED] [\(task.sourceSystem.rawValue)] \(task.title)")
    }

    public func clearCompletedTasks() {
        let completedCount = tasks.filter { $0.isCompleted }.count
        guard completedCount > 0 else { return }
        tasks.removeAll { $0.isCompleted }
        saveTasks()
        showToast("🧹 \(completedCount) ta bajarilgan vazifa ro'yxatdan tozalandi (history.md da saqlab qolindi).")
    }

    // MARK: - Synergy Reward Engine

    private func applySynergyReward(for task: TaskItem, isCompleting: Bool) {
        let sign: Double = isCompleting ? 1.0 : -1.0

        switch task.sourceSystem {
        case .general:
            if isCompleting {
                showToast("🟢 Vazifa bajarildi (Yashil) va history.md ga yozildi!")
            }

        case .exacc:
            let delta = (task.pointsValue > 0 ? task.pointsValue : 25.0) * sign
            exAcc.totalStandardCharge = max(0, exAcc.totalStandardCharge + delta)
            if let mIdx = exAcc.missions.firstIndex(where: { $0.isActive && !$0.isFaction }) {
                exAcc.missions[mIdx].earnedCharge = max(0, exAcc.missions[mIdx].earnedCharge + delta)
            }
            saveExAcc()
            if isCompleting {
                showToast("🟢 ExAcc Bajarildi: +\(formatPoints(abs(delta))) ball! (Jami: \(formatPoints(exAcc.totalStandardCharge)))")
            }

        case .sat:
            handleSATTaskCompletion(task, isCompleting: isCompleting)
        }
    }

    private func handleSATTaskCompletion(_ task: TaskItem, isCompleting: Bool) {
        let today = TaskItem.todayString()
        let lowerTitle = task.title.lowercased()

        if let topicIdx = satTracker.topics.firstIndex(where: {
            $0.id == task.linkedEntityId || lowerTitle.contains($0.title.lowercased().prefix(10))
        }) {
            var topic = satTracker.topics[topicIdx]
            let delta = (task.pointsValue > 0 ? task.pointsValue : 8.0) * (isCompleting ? 1.0 : -1.0)
            topic.currentScore = max(0, min(topic.potentialWeight, topic.currentScore + delta))

            if let cpIdx = topic.checkpoints.firstIndex(where: { $0.stage == task.satStage }) {
                topic.checkpoints[cpIdx].isCompleted = isCompleting
                topic.checkpoints[cpIdx].completedDate = isCompleting ? today : nil
            }

            topic.status = Self.computeSATStatus(current: topic.currentScore, potential: topic.potentialWeight)
            satTracker.topics[topicIdx] = topic
            saveSATTracker()

            if isCompleting {
                showToast("🟢 Score SAT: +\(formatPoints(abs(delta))) ball! Umumiy SAT: \(satTracker.totalSATScore) / 1600")
            }
        } else if isCompleting && task.satStage == .ingest {
            let inferredSection: SATSection = lowerTitle.contains("math") || lowerTitle.contains("quadratic") || lowerTitle.contains("exponential") || lowerTitle.contains("polynomial") || lowerTitle.contains("circle") || lowerTitle.contains("statistic") || lowerTitle.contains("probabilit") ? .math : .readingWriting
            let inferredCat: SATCategory = task.pointsValue >= 20 ? .kat1 : .kat2
            let inferredWeight = task.pointsValue > 0 ? round(task.pointsValue / 0.30) : 70.0
            let cleanTitle = task.title
                .replacingOccurrences(of: "[SAT Math] ", with: "")
                .replacingOccurrences(of: "[SAT English] ", with: "")
                .replacingOccurrences(of: " — Deep Focus (Ingest 30%)", with: "")
                .replacingOccurrences(of: " — Sunday Buffer (Ingest 30%)", with: "")
                .replacingOccurrences(of: " (Ingest 30%)", with: "")

            ingestNewSATTopic(
                title: cleanTitle,
                section: inferredSection,
                category: inferredCat,
                weight: inferredWeight,
                notes: task.notes,
                spawnIngestTask: false
            )
        }
    }

    public func ingestNewSATTopic(
        title: String,
        section: SATSection,
        category: SATCategory,
        weight: Double,
        notes: String = "",
        spawnIngestTask: Bool = true
    ) {
        let today = Date()
        let todayStr = TaskItem.todayString(from: today)
        let ingestScore = round(weight * 0.30 * 10) / 10.0
        let d1Score = round(weight * 0.20 * 10) / 10.0
        let d3Score = round(weight * 0.20 * 10) / 10.0
        let d14Score = round(weight * 0.15 * 10) / 10.0
        let d30Score = round(weight * 0.15 * 10) / 10.0

        func datePlus(_ days: Int) -> String {
            let d = Calendar.current.date(byAdding: .day, value: days, to: today) ?? today
            return TaskItem.todayString(from: d)
        }

        let topicId = UUID()
        let checkpoints: [SATReviewCheckpoint] = [
            SATReviewCheckpoint(stage: .day1, dueDate: datePlus(1), pointsDelta: d1Score),
            SATReviewCheckpoint(stage: .day3, dueDate: datePlus(3), pointsDelta: d3Score),
            SATReviewCheckpoint(stage: .day7, dueDate: datePlus(7), pointsDelta: 0),
            SATReviewCheckpoint(stage: .day14, dueDate: datePlus(14), pointsDelta: d14Score),
            SATReviewCheckpoint(stage: .day30, dueDate: datePlus(30), pointsDelta: d30Score)
        ]

        let newTopic = SATTopic(
            id: topicId,
            title: title,
            section: section,
            category: category,
            potentialWeight: weight,
            currentScore: ingestScore,
            learnedDate: todayStr,
            status: .ingested,
            checkpoints: checkpoints,
            trapsAndNotes: notes
        )

        satTracker.topics.append(newTopic)
        saveSATTracker()

        let day1Task = TaskItem(
            title: "[SAT SR] \(title) — Day 1 Review",
            isCompleted: false,
            sourceSystem: .sat,
            accumulatorSize: .small,
            satStage: .day1,
            linkedEntityId: topicId,
            scheduledDate: datePlus(1),
            startDate: todayStr,
            durationDays: 2,
            pointsValue: d1Score,
            notes: "24 soatlik xatolar tahlili va 5-10 ta tezkor mashq"
        )
        let day3Task = TaskItem(
            title: "[SAT SR] \(title) — Day 3 Recall",
            isCompleted: false,
            sourceSystem: .sat,
            accumulatorSize: .small,
            satStage: .day3,
            linkedEntityId: topicId,
            scheduledDate: datePlus(3),
            startDate: todayStr,
            durationDays: 4,
            pointsValue: d3Score,
            notes: "3-kunlik Active Recall va murakkab savollar"
        )
        tasks.insert(day3Task, at: 0)
        tasks.insert(day1Task, at: 0)
        saveTasks()

        if spawnIngestTask {
            appendHistoryLine("- [x] [{TIMESTAMP}] [SAT] [Ingest 30%] \(title) (+\(formatPoints(ingestScore)) ball)")
        }
        showToast("🚀 Yangi SAT Mavzu: \(title) (+\(formatPoints(ingestScore)) ball)! Jami SAT: \(satTracker.totalSATScore)/1600")
    }

    public func completeSATCheckpoint(topicId: UUID, checkpointId: UUID) {
        guard let tIdx = satTracker.topics.firstIndex(where: { $0.id == topicId }),
              let cIdx = satTracker.topics[tIdx].checkpoints.firstIndex(where: { $0.id == checkpointId }) else { return }

        let cp = satTracker.topics[tIdx].checkpoints[cIdx]
        let today = TaskItem.todayString()

        if !cp.isCompleted && cp.dueDate > today && !settings.allowEarlyFutureSATReviews {
            showToast("⚠️ Qat'iy Sana Filtri: \(cp.stage.shortLabel) sanasi (\(cp.dueDate)) hali kelmagan!")
            return
        }

        let newState = !cp.isCompleted
        satTracker.topics[tIdx].checkpoints[cIdx].isCompleted = newState
        satTracker.topics[tIdx].checkpoints[cIdx].completedDate = newState ? today : nil

        let sign: Double = newState ? 1.0 : -1.0
        let newScore = satTracker.topics[tIdx].currentScore + (cp.pointsDelta * sign)
        satTracker.topics[tIdx].currentScore = max(0, min(satTracker.topics[tIdx].potentialWeight, newScore))
        satTracker.topics[tIdx].status = Self.computeSATStatus(
            current: satTracker.topics[tIdx].currentScore,
            potential: satTracker.topics[tIdx].potentialWeight
        )

        let topicTitle = satTracker.topics[tIdx].title
        saveSATTracker()

        if newState {
            appendHistoryLine("- [x] [{TIMESTAMP}] [SAT] [\(cp.stage.shortLabel)] \(topicTitle) (+\(formatPoints(cp.pointsDelta)) ball)")
            showToast("🟢 \(topicTitle) (\(cp.stage.shortLabel)) bajarildi! Umumiy SAT: \(satTracker.totalSATScore)/1600")
        }
    }

    public func triggerMockPenalty(for topicId: UUID) {
        guard let tIdx = satTracker.topics.firstIndex(where: { $0.id == topicId }) else { return }
        var topic = satTracker.topics[tIdx]
        let penalty = round(topic.potentialWeight * 0.30 * 10) / 10.0
        topic.currentScore = max(0, topic.currentScore - penalty)
        topic.status = .vulnerable

        let today = Date()
        let step1Date = TaskItem.todayString(from: Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
        let step2Date = TaskItem.todayString(from: Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today)
        let halfRecovery = round((penalty / 2.0) * 10) / 10.0

        topic.checkpoints.append(SATReviewCheckpoint(stage: .fastTrack1, dueDate: step1Date, pointsDelta: halfRecovery))
        topic.checkpoints.append(SATReviewCheckpoint(stage: .fastTrack2, dueDate: step2Date, pointsDelta: halfRecovery))

        satTracker.topics[tIdx] = topic
        saveSATTracker()

        addTask(
            title: "[SAT Fast-Track 1] \(topic.title) — Error Log & 5 Target Questions",
            source: .sat,
            accumulator: .small,
            satStage: .fastTrack1,
            scheduledDate: step1Date,
            durationDays: 2,
            points: halfRecovery,
            notes: "Mock xato tahlili"
        )
        appendHistoryLine("- [!] [{TIMESTAMP}] [SAT MOCK PENALTY] \(topic.title) (-\(formatPoints(penalty)) ball muzlatildi)")
        showToast("⚠️ Mock Jarima: -\(formatPoints(penalty)) ball muzlatildi. Fast-Track ochildi!")
    }

    private func syncSATFactionObserverMission() {
        if let idx = exAcc.missions.firstIndex(where: { $0.isFaction && ($0.factionName == "score-sat-system" || $0.title.contains("SAT")) }) {
            exAcc.missions[idx].earnedCharge = Double(satTracker.totalSATScore)
        }
    }

    private static func computeSATStatus(current: Double, potential: Double) -> SATTopicStatus {
        guard potential > 0 else { return .notStarted }
        let ratio = current / potential
        switch ratio {
        case ..<0.05: return .notStarted
        case 0.05..<0.45: return .ingested
        case 0.45..<0.65: return .refined50
        case 0.65..<0.80: return .refined70
        case 0.80..<0.96: return .consolidated85
        default: return .mastered100
        }
    }

    public func addExAccMission(
        title: String,
        tier: MissionTier,
        accType: AccType,
        volume: VolumeType,
        deadlineDate: String,
        targetCharge: Double
    ) {
        let activeCount = exAcc.missions.filter { $0.isActive }.count
        if activeCount >= 2 {
            showToast("⚠️ WIP Limit (Max 2 Acc): Yangi acc ochishdan oldin mavjud 2 ta faol acc'dan birini yakunlang!")
            return
        }
        let mission = ExAccMission(
            title: title,
            tier: tier,
            accType: accType,
            volume: volume,
            isFaction: false,
            deadlineDate: deadlineDate,
            earnedCharge: 0,
            targetCharge: targetCharge,
            isActive: true
        )
        exAcc.missions.append(mission)
        saveExAcc()
        appendHistoryLine("- [EXACC+] [{TIMESTAMP}] Yangi Missiya: \(title)")
        showToast("🚀 Yangi ExAcc Missiya qo'shildi!")
    }

    public func copyGeminiSyncReportToClipboard() -> String {
        let today = TaskItem.todayString()
        let completedToday = tasks.filter { $0.isCompleted }
        let overdueSAT = satTracker.topics.filter { $0.hasOverdueCheckpoint }

        var report = """
        # 📊 FocusCorner Synergy Report (\(today))
        - **Umumiy SAT Balli:** \(satTracker.totalSATScore) / 1600 (Math: \(satTracker.currentMathScore) | RW: \(satTracker.currentRWScore))
        - **ExAcc Standart Zaryad:** \(formatPoints(exAcc.totalStandardCharge)) ball (Faol Acc: \(exAcc.activeMissionsCount)/2)

        ## ✅ Bajarilgan Vazifalar:
        """
        if completedToday.isEmpty {
            report += "\n- Hozircha belgilangan vazifa yo'q."
        } else {
            for t in completedToday {
                let pts = t.pointsValue > 0 ? " (+\(formatPoints(t.pointsValue)) ball)" : ""
                report += "\n- [x] [\(t.sourceSystem.rawValue)] \(t.title)\(pts)"
            }
        }

        if !overdueSAT.isEmpty {
            report += "\n\n## ⚠️ Muddati O'tgan SAT Takrorlashlar:"
            for top in overdueSAT {
                report += "\n- \(top.title) (Joriy: \(formatPoints(top.currentScore))/\(formatPoints(top.potentialWeight)))"
            }
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        showToast("📋 Gemini uchun hisobot buferga (Clipboard) nusxalandi!")
        return report
    }

    private func startSafetyProtocolTimer() {
        protocolTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSafetyProtocolStatus()
            }
        }
    }

    public func refreshSafetyProtocolStatus() {
        let today = TaskItem.todayString()
        let hasHeavyStarted = tasks.contains { $0.isCompleted && $0.scheduledDate == today }
        let status = SafetyProtocolMonitor.currentStatus(hasStartedHeavyTaskToday: hasHeavyStarted)
        self.statusBannerMessage = status.statusBanner
    }

    private func startDirectoryWatcher() {
        directoryFileDescriptor = open(baseDirURL.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename, .extend],
            queue: DispatchQueue.main
        )
        let fdCopy = directoryFileDescriptor
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self, !self.isInternalWriteInProgress else { return }
                self.loadAllData()
            }
        }
        source.setCancelHandler {
            close(fdCopy)
        }
        source.resume()
        self.directoryWatcher = source
    }

    public func formatPoints(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
