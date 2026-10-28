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
    private var watcherDebounceWorkItem: DispatchWorkItem?
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
        migrateToV5_2Oct18SynergyIfNeeded()
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
            - [x] [2026-10-16 20:15] [SAT] [Day 3 +20%] Ratios, Rates, Percentages & Units — Day 3 Recall (+8 ball)
            - [x] [2026-10-16 21:10] [SAT] [Ingest 30%] Words in Context — Deep Focus (+21 ball)
            - [x] [2026-10-18 14:20] [GENERAL] Investment Accni yaratish va boshlash
            - [x] [2026-10-18 14:40] [GENERAL] Nevroz Acc yaratish va boshlash
            - [x] [2026-10-18 15:10] [GENERAL] GU Tizimini yaratish
            - [x] [2026-10-18 16:05] [SAT] [Day 7] Linear Functions & Systems — Day 7 Review (+12 ball)
            - [x] [2026-10-18 16:30] [SAT] [Day 1] Words in Context — Day 1 Review (+8 ball)

            """
            try? header.write(to: historyFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Universal resilient decoder that handles BOTH `[TaskItem]` array AND `{"tasks": [TaskItem]}` envelope!
    nonisolated public static func decodeTasksResiliently(from data: Data) -> [TaskItem]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let arr = try? decoder.decode([TaskItem].self, from: data) {
            return arr
        }
        if let env = try? decoder.decode(TasksFileEnvelope.self, from: data) {
            return env.tasks
        }
        // Fallback decoder without strict iso8601 in case timestamps are custom or missing
        let fallbackDecoder = JSONDecoder()
        if let arr = try? fallbackDecoder.decode([TaskItem].self, from: data) {
            return arr
        }
        if let env = try? fallbackDecoder.decode(TasksFileEnvelope.self, from: data) {
            return env.tasks
        }
        return nil
    }

    public func reloadFromDiskSafely() {
        guard !isInternalWriteInProgress else { return }
        loadAllData()
    }

    public func loadAllData() {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Settings (NEVER re-save inside loadAllData unless file is missing, preventing FSEvents loops!)
        if let data = try? Data(contentsOf: settingsFileURL),
           var loaded = try? decoder.decode(AppSettings.self, from: data) {
            loaded.isGhostClickThrough = false
            loaded.isRulesPinned = false
            if loaded.rulesOpacity < 0.85 { loaded.rulesOpacity = 0.96 }
            if loaded.notesOpacity < 0.85 { loaded.notesOpacity = 0.96 }
            if self.settings != loaded {
                self.settings = loaded
            }
        } else if !fm.fileExists(atPath: settingsFileURL.path) {
            self.settings = AppSettings()
            saveSettings()
        }

        // 2. Rules
        if let data = try? Data(contentsOf: rulesFileURL),
           let loaded = try? decoder.decode([RuleItem].self, from: data),
           !loaded.isEmpty {
            if self.rules != loaded {
                self.rules = loaded
            }
        } else if !fm.fileExists(atPath: rulesFileURL.path) {
            self.rules = RuleItem.defaultRPARules
            saveRules()
        }

        // 3. SAT Tracker
        if let data = try? Data(contentsOf: satFileURL),
           let loaded = try? decoder.decode(SATTrackerState.self, from: data) {
            if self.satTracker != loaded {
                self.satTracker = loaded
            }
        } else if !fm.fileExists(atPath: satFileURL.path) {
            self.satTracker = SATTrackerState()
            saveSATTracker()
        }

        // 4. ExAcc
        if let data = try? Data(contentsOf: exAccFileURL),
           let loaded = try? decoder.decode(ExAccState.self, from: data) {
            if self.exAcc != loaded {
                self.exAcc = loaded
                syncSATFactionObserverMission()
            }
        } else if !fm.fileExists(atPath: exAccFileURL.path) {
            self.exAcc = ExAccState()
            syncSATFactionObserverMission()
            saveExAcc()
        }

        // 5. Tasks (Resilient to both Array and {"tasks": [...]} & Never Wipes Non-Empty Corrupt File!)
        if let data = try? Data(contentsOf: tasksFileURL), !data.isEmpty {
            if let loaded = Self.decodeTasksResiliently(from: data) {
                if self.tasks != loaded {
                    self.tasks = loaded
                }
            } else {
                // Quarantine unreadable file to backups rather than wiping user's tasks!
                let stamp = Int(Date().timeIntervalSince1970)
                let quarantineURL = backupsDirURL.appendingPathComponent("unreadable_tasks_\(stamp).json")
                try? data.write(to: quarantineURL)
            }
        } else if !fm.fileExists(atPath: tasksFileURL.path) {
            self.tasks = []
            saveTasks()
        }

        // 6. History
        if let hist = try? String(contentsOf: historyFileURL, encoding: .utf8) {
            if self.historyContent != hist {
                self.historyContent = hist
            }
        }
    }

    /// Synchronizes the exact Oct 18, 2026 schedule, SAT 654 (Math 307 | RW 347), ExAcc 170, and tasks
    @discardableResult
    public func syncOct18ScheduleAndScores(force: Bool = false) -> String {
        let today = TaskItem.todayString()
        let tomorrowDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrow = TaskItem.todayString(from: tomorrowDate)
        let fourDaysDate = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
        let fourDays = TaskItem.todayString(from: fourDaysDate)

        // Ensure SAT Tracker is at least 654 (Math 307 | RW 347)
        if satTracker.totalSATScore < 654 || force {
            satTracker = SATTrackerState(
                systemVersion: "SSS v5.2 (1-3-7-14-30 Verified • Oct 18)",
                baseMathScore: 200,
                baseRWScore: 200,
                topics: SATTrackerState.initialUserTopics
            )
            saveSATTracker()
        }

        if exAcc.totalStandardCharge < 170 || force {
            exAcc.totalStandardCharge = 170
            syncSATFactionObserverMission()
            saveExAcc()
        }

        let oct18Tasks: [TaskItem] = [
            // TODAY'S ACTIVE TASKS (18-Oktabr, Yakshanba — Bugun • Ko'k)
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct18-sat-sr-1"),
                title: "[SAT SR] Day 7: Transitions (+10.5) | Day 1: Exponential (+14)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .small,
                satStage: .day7,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 24.5,
                notes: "17:00 – 18:30 Spaced Repetition bloki"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct18-sat-math-quad"),
                title: "[SAT Math] Quadratic Functions & Parabolas — Deep Focus (+24 ball)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 24.0,
                notes: "18:45 – 19:45 Sunday Buffer mavzusi (Vertex, Discriminant, Vieta)"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct18-ae-checkin"),
                title: "⚡ A&E Check-in: SAT Mani Acc (Audit & Scoring)",
                isCompleted: false,
                sourceSystem: .exacc,
                accumulatorSize: .small,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 10.0,
                notes: "20:00 – 20:30 Haftalik audit"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct18-invest-buffer"),
                title: "ExAcc: Sunday Buffer — Invest Midi Acc (Haftalik sarhisob)",
                isCompleted: false,
                sourceSystem: .exacc,
                accumulatorSize: .small,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 10.0,
                notes: "21:45 – 22:15 Investitsiya Midi Acc"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct18-gu-rank1"),
                title: "[Gu Rank 1 - Initial] Kun 1: Awakening & Tana Bilan Yarashish",
                isCompleted: false,
                sourceSystem: .general,
                accumulatorSize: .small,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 10.0,
                notes: "22:30 – 23:00 Ichki kultivatsiya bloki"
            ),

            // UPCOMING MULTI-DAY TASKS (Keyingi kunlar — 19-Oktabr Dushanba & 22-Oktabr)
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct19-sat-rw-punct"),
                title: "[SAT RW] Boundaries & Punctuation — Deep Focus (Ingest 30%) (+21 ball)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: tomorrow,
                startDate: today,
                durationDays: 2,
                pointsValue: 21.0,
                notes: "Dushanba (19-Okt) kuniga ko'chirilgan — Semicolons, Colons, Dashes & Comma Splices"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct19-sat-math-ineq"),
                title: "[SAT Math] Linear Inequalities & Word Problems — Ingest 30% (+24 ball)",
                isCompleted: false,
                sourceSystem: .sat,
                accumulatorSize: .big,
                satStage: .ingest,
                scheduledDate: tomorrow,
                startDate: today,
                durationDays: 2,
                pointsValue: 24.0,
                notes: "Dushanba (19-Okt) asosiy Math bloki"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "oct22-exacc-deep"),
                title: "[ExAcc] Haftalik Mini-Acc Deep Work Bloki (+25 ball)",
                isCompleted: false,
                sourceSystem: .exacc,
                accumulatorSize: .medium,
                satStage: .none,
                scheduledDate: fourDays,
                startDate: today,
                durationDays: 5,
                pointsValue: 25.0,
                notes: "Payshanba (22-Okt) — Ko'kish oq rejim"
            ),

            // COMPLETED TASKS (Bajarilganlar — Yashil)
            TaskItem(
                id: TaskItem.deterministicUUID(from: "done-oct18-linear-d7"),
                title: "[SAT] Linear Functions & Systems — Day 7 Review (+12 ball)",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .sat,
                accumulatorSize: .small,
                satStage: .day7,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 12.0,
                notes: "Bajarildi ✅ (+12 ball -> 68/80 Consolidated)"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "done-oct18-words-d1"),
                title: "[SAT] Words in Context — Day 1 Review (+8 ball)",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .sat,
                accumulatorSize: .small,
                satStage: .day1,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 8.0,
                notes: "Bajarildi ✅ (+8 ball -> 29/70)"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "done-oct18-inv-init"),
                title: "[GENERAL] Investment Accni yaratish va boshlash",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .general,
                accumulatorSize: .none,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 0,
                notes: "Bajarildi ✅"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "done-oct18-nevroz-init"),
                title: "[GENERAL] Nevroz Acc yaratish va boshlash",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .general,
                accumulatorSize: .none,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 0,
                notes: "Bajarildi ✅"
            ),
            TaskItem(
                id: TaskItem.deterministicUUID(from: "done-oct18-gu-init"),
                title: "[GENERAL] GU Tizimini yaratish",
                isCompleted: true,
                completedAt: Date(),
                sourceSystem: .general,
                accumulatorSize: .none,
                satStage: .none,
                scheduledDate: today,
                startDate: today,
                durationDays: 1,
                pointsValue: 0,
                notes: "Bajarildi ✅"
            )
        ]

        self.tasks = oct18Tasks
        saveTasks()
        showToast("⚡ 18-Oktabr vazifalari va 654 SAT ball to'liq sinxronlandi!")
        return "✅ 18-Oktabr (Yakshanba) jadvali sinxronlandi:\n• SAT: \(satTracker.totalSATScore)/1600 (Math: \(satTracker.currentMathScore) | RW: \(satTracker.currentRWScore))\n• ExAcc: \(formatPoints(exAcc.totalStandardCharge)) ball\n• Bugungi faol vazifalar: 5 ta (Ochiq ko'k)\n• Keyingi kunlar (Dushanba+): 3 ta\n• Bajarilganlar: 5 ta (Yashil)"
    }

    private func migrateToV5_2Oct18SynergyIfNeeded() {
        // If tasks are empty or migration hasn't run yet, sync Oct 18 tasks & scores cleanly
        if !settings.migratedV5_2Oct18TerminalBackup || tasks.isEmpty {
            _ = syncOct18ScheduleAndScores(force: true)
            settings.migratedV3Oct16 = true
            settings.migratedV3_1BlueSpectrum = true
            settings.migratedV5_2Oct18TerminalBackup = true
            saveSettings()
        }
    }

    public func setExplicitSATScores(math: Int, rw: Int) -> String {
        let clampedMath = max(200, min(800, math))
        let clampedRW = max(200, min(800, rw))
        let mathTopicsSum = satTracker.topics.filter { $0.section == .math }.reduce(0.0) { $0 + $1.currentScore }
        let rwTopicsSum = satTracker.topics.filter { $0.section == .readingWriting }.reduce(0.0) { $0 + $1.currentScore }
        satTracker.baseMathScore = Double(clampedMath) - mathTopicsSum
        satTracker.baseRWScore = Double(clampedRW) - rwTopicsSum
        saveSATTracker()
        return "✅ SAT Balli yangilandi: \(satTracker.totalSATScore) / 1600 (Math: \(satTracker.currentMathScore) | RW: \(satTracker.currentRWScore))"
    }

    public func RPAResetCustomOrigin() {
        settings.rulesOriginX = nil
        settings.rulesOriginY = nil
    }

    // MARK: - Atomic JSON Persistence

    private func atomicWriteJSON<T: Encodable>(_ value: T, to url: URL) {
        isInternalWriteInProgress = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
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

    nonisolated private static func formattedTimestamp(from date: Date = Date()) -> String {
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
        } else {
            let inferred = TaskItem.inferPointsFromTitle(trimmed)
            if inferred > 0 {
                resolvedPoints = inferred
            } else if source == .exacc {
                resolvedPoints = accumulator == .none ? 25 : accumulator.points
            } else if source == .sat {
                resolvedPoints = satStage == .ingest ? 21 : 8
            } else {
                resolvedPoints = 0
            }
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

    public func setTaskOverdueByDays(_ task: TaskItem, overdueDays: Int = 1) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let calDiff = TaskItem.daysBetween(from: tasks[idx].startDate, to: TaskItem.todayString())
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
        BackupManager.shared.createAutoBackupIfNeeded(reason: "Bajarilganlarni Tozalash Oldidan")
        tasks.removeAll { $0.isCompleted }
        saveTasks()
        showToast("🧹 \(completedCount) ta bajarilgan vazifa ro'yxatdan tozalandi (history.md va backupda saqlandi).")
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
            let inferredSection: SATSection = lowerTitle.contains("math") || lowerTitle.contains("quadratic") || lowerTitle.contains("exponential") || lowerTitle.contains("polynomial") || lowerTitle.contains("circle") || lowerTitle.contains("statistic") || lowerTitle.contains("probabilit") || lowerTitle.contains("inequalit") ? .math : .readingWriting
            let inferredCat: SATCategory = task.pointsValue >= 20 ? .kat1 : .kat2
            let inferredWeight = task.pointsValue > 0 ? round(task.pointsValue / 0.30) : 70.0
            let cleanTitle = task.cleanDisplayTitle

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
        let d7Score = round(weight * 0.15 * 10) / 10.0
        let d14Score = round(weight * 0.15 * 10) / 10.0

        func datePlus(_ days: Int) -> String {
            let d = Calendar.current.date(byAdding: .day, value: days, to: today) ?? today
            return TaskItem.todayString(from: d)
        }

        let topicId = UUID()
        let checkpoints: [SATReviewCheckpoint] = [
            SATReviewCheckpoint(stage: .day1, dueDate: datePlus(1), pointsDelta: d1Score),
            SATReviewCheckpoint(stage: .day3, dueDate: datePlus(3), pointsDelta: d3Score),
            SATReviewCheckpoint(stage: .day7, dueDate: datePlus(7), pointsDelta: d7Score),
            SATReviewCheckpoint(stage: .day14, dueDate: datePlus(14), pointsDelta: d14Score),
            SATReviewCheckpoint(stage: .day30, dueDate: datePlus(30), pointsDelta: 0)
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

    private func syncSATFactionObserverMission() {
        if let idx = exAcc.missions.firstIndex(where: { $0.isFaction && ($0.factionName == "score-sat-system" || $0.title.contains("SAT")) }) {
            exAcc.missions[idx].earnedCharge = Double(satTracker.totalSATScore)
        }
    }

    nonisolated private static func computeSATStatus(current: Double, potential: Double) -> SATTopicStatus {
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
                self.watcherDebounceWorkItem?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        guard let self = self, !self.isInternalWriteInProgress else { return }
                        self.loadAllData()
                    }
                }
                self.watcherDebounceWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
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
