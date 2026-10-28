import Foundation
import AppKit
import Combine

public struct RPADayColumnInfo: Identifiable, Equatable {
    public var id: String { dateString }
    public let title: String        // "Kecha", "Bugun", "Ertaga"
    public let shortDate: String    // "20-Okt", "21-Okt", "22-Okt"
    public let dateString: String   // "2026-10-20"
    public let isToday: Bool
}

@MainActor
public final class StorageManager: ObservableObject {
    public static let shared = StorageManager()

    @Published public var rules: [RuleItem] = []
    @Published public var rpaArchive: [RPAArchivedDayEntry] = []
    @Published public var rpaHistoryMarkdown: String = ""
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
    public let rpaArchiveFileURL: URL
    public let rpaHistoryFileURL: URL
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
    private var lastObservedTodayString: String = ""

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirURL = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.backupsDirURL = baseDirURL.appendingPathComponent("backups", isDirectory: true)
        self.rulesFileURL = baseDirURL.appendingPathComponent("rules.json")
        self.rpaArchiveFileURL = baseDirURL.appendingPathComponent("rpa_archive.json")
        self.rpaHistoryFileURL = baseDirURL.appendingPathComponent("rpa_history.md")
        self.tasksFileURL = baseDirURL.appendingPathComponent("tasks.json")
        self.satFileURL = baseDirURL.appendingPathComponent("sat_tracker.json")
        self.exAccFileURL = baseDirURL.appendingPathComponent("exacc.json")
        self.settingsFileURL = baseDirURL.appendingPathComponent("settings.json")
        self.historyFileURL = baseDirURL.appendingPathComponent("history.md")
        self.lastObservedTodayString = TaskItem.todayString()

        ensureDirectoriesAndBackups()
        loadAllData()
        migrateToV5_2Oct18SynergyIfNeeded()
        autoRolloverAndArchiveRPADates()
        syncGuApertureNoErrorIfInstalled()
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
            - [x] [2026-10-18 16:05] [SAT] [Day 7] Linear Functions & Systems — Day 7 Review (+12 ball)
            - [x] [2026-10-20 21:30] [SAT] [Day 1] Boundaries & Punctuation (+14 ball) va Linear Inequalities (+8 ball)
            - [x] [2026-10-21 22:15] [SAT] [Ingest 30%] Command of Evidence (+21 ball) va Verb Tense Day 1 (+8 ball)

            """
            try? header.write(to: historyFileURL, atomically: true, encoding: .utf8)
        }

        if !fm.fileExists(atPath: rpaHistoryFileURL.path) {
            let rpaHeader = """
            # 🛡 FocusCorner RPA — Kunlik Anti-Odat va Gu No-Error (20%) Arxiv Tarixi
            > Har kuni sanalar almashganda kechagi va oldingi kunlarning RPA holati avtomatik ravishda ushbu faylga arxivlanadi.

            """
            try? rpaHeader.write(to: rpaHistoryFileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 3-Day Dynamic RPA Columns (Kecha, Bugun, Ertaga) & Gu No-Error 20% Sector

    public var rpaYesterdayString: String {
        let d = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return TaskItem.todayString(from: d)
    }

    public var rpaTodayString: String {
        TaskItem.todayString(from: Date())
    }

    public var rpaTomorrowString: String {
        let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return TaskItem.todayString(from: d)
    }

    public var rpaThreeDayColumns: [RPADayColumnInfo] {
        let cal = Calendar.current
        let now = Date()
        let yDate = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let tmDate = cal.date(byAdding: .day, value: 1, to: now) ?? now
        return [
            RPADayColumnInfo(
                title: "Kecha",
                shortDate: Self.shortUzbekDayMonth(from: yDate),
                dateString: TaskItem.todayString(from: yDate),
                isToday: false
            ),
            RPADayColumnInfo(
                title: "Bugun",
                shortDate: Self.shortUzbekDayMonth(from: now),
                dateString: TaskItem.todayString(from: now),
                isToday: true
            ),
            RPADayColumnInfo(
                title: "Ertaga",
                shortDate: Self.shortUzbekDayMonth(from: tmDate),
                dateString: TaskItem.todayString(from: tmDate),
                isToday: false
            )
        ]
    }

    nonisolated public static func shortUzbekDayMonth(from date: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let month = cal.component(.month, from: date)
        let months = ["Yan", "Fev", "Mar", "Apr", "May", "Iyn", "Iyl", "Avg", "Sen", "Okt", "Noy", "Dek"]
        let mName = (month >= 1 && month <= 12) ? months[month - 1] : "Okt"
        return String(format: "%02d-%@", day, mName)
    }

    public func rpaXCount(for dateString: String) -> Int {
        rules.filter { $0.isMarkedX(on: dateString) }.count
    }

    public var todayRPAXCount: Int {
        rpaXCount(for: rpaTodayString)
    }

    public var yesterdayRPAXCount: Int {
        rpaXCount(for: rpaYesterdayString)
    }

    /// Gu Internal Cultivation: 90% Natural Aptitude -> 20% No-Error (Xatolarsiz Poklik) Sektori (0..20%)
    public func guNoErrorSectorScore(for dateString: String) -> Int {
        guard !rules.isEmpty else { return 20 }
        let xCnt = rpaXCount(for: dateString)
        let cleanCnt = max(0, rules.count - xCnt)
        return max(0, min(20, Int(round(20.0 * Double(cleanCnt) / Double(rules.count)))))
    }

    public var currentGuNoErrorScore: Int {
        guNoErrorSectorScore(for: rpaTodayString)
    }

    public func toggleRPAMarkX(_ rule: RuleItem, on dateString: String) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let wasMarked = rules[idx].xMarkedDates.contains(dateString)
        if wasMarked {
            rules[idx].xMarkedDates.removeAll { $0 == dateString }
        } else {
            rules[idx].xMarkedDates.append(dateString)
            rules[idx].xMarkedDates = Array(Set(rules[idx].xMarkedDates)).sorted()
        }
        saveRules()
        autoRolloverAndArchiveRPADates()
        syncGuApertureNoErrorIfInstalled()

        let statusSymbol = wasMarked ? "[ — ] Pok holatga qaytarildi" : "[ X ] Xato qayd etildi"
        appendHistoryLine("- [RPA] [{TIMESTAMP}] [\(dateString)] \(rule.title) -> \(statusSymbol) (Gu No-Error: \(currentGuNoErrorScore)/20%)")
        if !settings.isNotesCollapsed {
            showToast(wasMarked
                ? "🛡 RPA Toza: '\(rule.title)' (\(dateString)) X olindi • Gu No-Error: \(currentGuNoErrorScore)/20%"
                : "⚠️ RPA [X] belgilandi (\(dateString)) • Gu No-Error Sektori: \(currentGuNoErrorScore)/20%"
            )
        }
    }

    /// Har kuni sana yangilanganda kechadan oldingi kunlarni va joriy ko'rsatkichlarni avtomatik arxivlaydi
    public func autoRolloverAndArchiveRPADates() {
        let todayStr = rpaTodayString
        let yesterdayStr = rpaYesterdayString
        let tomorrowStr = rpaTomorrowString

        // Collect all dates ever touched + yesterday + any past dates
        var candidateDates = Set<String>()
        for r in rules {
            for d in r.xMarkedDates {
                candidateDates.insert(d)
            }
        }
        if !settings.lastPromptDate.isEmpty && settings.lastPromptDate < todayStr {
            candidateDates.insert(settings.lastPromptDate)
        }
        candidateDates.insert(yesterdayStr)

        var archiveChanged = false
        let nowHuman = Self.formattedTimestamp()

        for dateStr in candidateDates.sorted() {
            // Only archive dates up to today (do not archive tomorrow yet unless it passes)
            guard dateStr <= todayStr else { continue }
            let violated = rules.filter { $0.isMarkedX(on: dateStr) }.map { $0.title }
            let clean = rules.filter { !$0.isMarkedX(on: dateStr) }.map { $0.title }
            let entry = RPAArchivedDayEntry(
                dateString: dateStr,
                violatedHabitTitles: violated,
                cleanHabitTitles: clean,
                totalHabitsCount: rules.count,
                xCount: violated.count,
                guNoErrorScore: guNoErrorSectorScore(for: dateStr),
                archivedAt: nowHuman
            )
            if let existingIdx = rpaArchive.firstIndex(where: { $0.dateString == dateStr }) {
                if rpaArchive[existingIdx].violatedHabitTitles != entry.violatedHabitTitles ||
                   rpaArchive[existingIdx].totalHabitsCount != entry.totalHabitsCount {
                    rpaArchive[existingIdx] = entry
                    archiveChanged = true
                }
            } else {
                rpaArchive.append(entry)
                archiveChanged = true
            }
        }

        // Prune xMarkedDates older than 14 days from active rules.json once safely in rpaArchive
        let activeWindowDates = Set([yesterdayStr, todayStr, tomorrowStr])
        var rulesPruned = false
        for i in rules.indices {
            let beforeCount = rules[i].xMarkedDates.count
            rules[i].xMarkedDates = rules[i].xMarkedDates.filter { d in
                activeWindowDates.contains(d) || d >= yesterdayStr
            }
            if rules[i].xMarkedDates.count != beforeCount {
                rulesPruned = true
            }
        }
        if rulesPruned {
            saveRules()
        }

        if archiveChanged {
            rpaArchive.sort { $0.dateString > $1.dateString }
            saveRPAArchive()
            rebuildRPAHistoryMarkdown()
        } else if rpaHistoryMarkdown.isEmpty {
            rebuildRPAHistoryMarkdown()
        }
    }

    private func rebuildRPAHistoryMarkdown() {
        var lines: [String] = [
            "# 🛡 FocusCorner RPA — Kunlik Anti-Odat va Gu No-Error (20%) Arxiv Tarixi",
            "> Har kuni sanalar almashganda avtomatik yangilanadi va saqlab boriladi.",
            ""
        ]
        for item in rpaArchive.sorted(by: { $0.dateString > $1.dateString }) {
            let badge = item.xCount == 0 ? "✅ POK (0 ta X)" : "⚠️ \(item.xCount) ta [X]"
            lines.append("### 📅 \(item.dateString) — Gu No-Error: \(item.guNoErrorScore)/20% • \(badge)")
            if !item.violatedHabitTitles.isEmpty {
                for v in item.violatedHabitTitles {
                    lines.append("- `[ X ]` \(v)")
                }
            }
            for c in item.cleanHabitTitles {
                lines.append("- `[ — ]` \(c)")
            }
            lines.append("")
        }
        let content = lines.joined(separator: "\n")
        self.rpaHistoryMarkdown = content
        isInternalWriteInProgress = true
        try? content.write(to: rpaHistoryFileURL, atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isInternalWriteInProgress = false
        }
    }

    /// Agar foydalanuvchi Mac'ida Gu Primeval Aperture (~/.gu_aperture/state.json) bo'lsa, 20% No-Error sektorini bevosita sinxronlaydi
    public func syncGuApertureNoErrorIfInstalled() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let guStateURL = home.appendingPathComponent(".gu_aperture/state.json")
        guard FileManager.default.fileExists(atPath: guStateURL.path),
              let data = try? Data(contentsOf: guStateURL),
              var jsonObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        let score = currentGuNoErrorScore
        var changed = false
        if let oldVal = jsonObj["pillarNoErrors"] as? Int, oldVal != score {
            jsonObj["pillarNoErrors"] = score
            changed = true
        } else if jsonObj["pillarNoErrors"] == nil {
            jsonObj["pillarNoErrors"] = score
            changed = true
        }
        if changed, let updatedData = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: guStateURL, options: .atomic)
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

        // 2. Rules (RPA 3-Day Anti-Habits)
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

        // 2B. RPA Archive
        if let data = try? Data(contentsOf: rpaArchiveFileURL),
           let loaded = try? decoder.decode([RPAArchivedDayEntry].self, from: data) {
            if self.rpaArchive != loaded {
                self.rpaArchive = loaded
            }
        } else if !fm.fileExists(atPath: rpaArchiveFileURL.path) {
            self.rpaArchive = []
            saveRPAArchive()
        }

        if let rpaMd = try? String(contentsOf: rpaHistoryFileURL, encoding: .utf8) {
            self.rpaHistoryMarkdown = rpaMd
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

    @discardableResult
    public func syncOct18ScheduleAndScores(force: Bool = false) -> String {
        return syncTodayScheduleAndScores(force: force)
    }

    /// Synchronizes the verified Oct 22, 2026 schedule, SAT 791 (Math 345 | RW 446), ExAcc 230, and 3-day RPA rules
    @discardableResult
    public func syncTodayScheduleAndScores(force: Bool = false) -> String {
        if satTracker.totalSATScore < 791 || force {
            satTracker = SATTrackerState(
                systemVersion: "SSS v6.5 (1-3-7-14-30 Verified • Oct 22)",
                baseMathScore: 208,
                baseRWScore: 233.5,
                topics: SATTrackerState.initialUserTopics
            )
            saveSATTracker()
        }

        if exAcc.totalStandardCharge < 230 || force {
            exAcc.totalStandardCharge = 230
            syncSATFactionObserverMission()
            saveExAcc()
        }

        // Upgrade legacy generic reminders to the 3 core RPA Anti-Habits if still on old default
        if rules.isEmpty || rules.first?.title.contains("Fokus vaqtida telefon") == true {
            let existingDates = rules.flatMap { $0.xMarkedDates }
            var defaults = RuleItem.defaultRPARules
            if !existingDates.isEmpty && !defaults.isEmpty {
                defaults[0].xMarkedDates = Array(Set(existingDates)).sorted()
            }
            self.rules = defaults
            saveRules()
        }

        if tasks.isEmpty || force {
            let oct22Tasks: [TaskItem] = [
                // BUGUNGI VAZIFALAR (2026-10-22, Payshanba — Har bir takrorlash ALOHIDA SATRDA!)
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-sat-sr-punct-d3"),
                    title: "[SAT SR] Boundaries & Punctuation — Day 3 Recall (+14 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .small,
                    satStage: .day3,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 14.0,
                    notes: "17:25 – 18:30 Oraliq takrorlash bloki"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-sat-sr-ineq-d3"),
                    title: "[SAT SR] Linear Inequalities & Word Problems — Day 3 Recall (+8 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .small,
                    satStage: .day3,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 8.0,
                    notes: "17:25 – 18:30 Oraliq takrorlash bloki"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-sat-sr-coe-d1"),
                    title: "[SAT SR] Command of Evidence — Day 1 Review (+14 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .small,
                    satStage: .day1,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 14.0,
                    notes: "21-Oktabr o'zlashtirilgan Command of Evidence bo'yicha Day 1 Review"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-sat-math-poly"),
                    title: "[SAT Math] Polynomials, Radicals & Rational Equations — Deep Focus (Ingest 30%) (+24 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .big,
                    satStage: .ingest,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 24.0,
                    notes: "Kat-1 Math asosiy darsi: ildizlar, ratsional tenglamalar va ko'phadlar"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-exacc-small4"),
                    title: "[EXACC] Small Acc #4: Moliyaviy sog'lomlik & Red Flags (+10 ball)",
                    isCompleted: false,
                    sourceSystem: .exacc,
                    accumulatorSize: .small,
                    satStage: .none,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 10.0,
                    notes: "Investitsiya Midi Acc: moliyaviy xavf signallari"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct22-gu-d5"),
                    title: "[Gu Rank 1 - Initial] Kun 5: Issiqlikda 1sm Tizza & Oqar Suv (+10 ball)",
                    isCompleted: false,
                    sourceSystem: .general,
                    accumulatorSize: .small,
                    satStage: .none,
                    scheduledDate: "2026-10-22",
                    startDate: "2026-10-22",
                    durationDays: 1,
                    pointsValue: 10.0,
                    notes: "Tana bilan ishlash va jismoniy mikro-odat"
                ),

                // KEYINGI KUNLAR REJASI (Quadratics 25-Oktabr Sunday Bufferga ko'chirilgan!)
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct23-sat-sr-wic-d7"),
                    title: "[SAT SR] Words in Context — Day 7 Review (+10.5 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .small,
                    satStage: .day7,
                    scheduledDate: "2026-10-23",
                    startDate: "2026-10-22",
                    durationDays: 2,
                    pointsValue: 10.5,
                    notes: "23-Oktabr (Juma) 18:25 bloki"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct23-sat-sr-verb-d3"),
                    title: "[SAT SR] Verb Tense, Modifiers & Parallelism — Day 3 Recall (+8 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .small,
                    satStage: .day3,
                    scheduledDate: "2026-10-23",
                    startDate: "2026-10-22",
                    durationDays: 2,
                    pointsValue: 8.0,
                    notes: "23-Oktabr (Juma) 18:25 bloki"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct23-sat-math-exp"),
                    title: "[SAT Kat-1 Math] Exponential Functions (Ingest 30%) & Basic Statistics (+29 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .big,
                    satStage: .ingest,
                    scheduledDate: "2026-10-23",
                    startDate: "2026-10-22",
                    durationDays: 2,
                    pointsValue: 29.0,
                    notes: "23-Oktabr (Juma) 19:30 asosiy darsi"
                ),
                TaskItem(
                    id: TaskItem.deterministicUUID(from: "oct25-sat-math-quad"),
                    title: "[SAT Math] Quadratic Functions & Parabolas — Deep Focus (+24 ball)",
                    isCompleted: false,
                    sourceSystem: .sat,
                    accumulatorSize: .big,
                    satStage: .ingest,
                    scheduledDate: "2026-10-25",
                    startDate: "2026-10-22",
                    durationDays: 4,
                    pointsValue: 24.0,
                    notes: "25-Oktabr (Yakshanba, Sunday Buffer 14:30 – 17:00) qulay seansga ko'chirilgan"
                )
            ]
            self.tasks = oct22Tasks
            saveTasks()
        }

        autoRolloverAndArchiveRPADates()
        return "✅ 22-Oktabr jadvali va RPA 3-kunlik tizimi sinxronlandi: SAT \(satTracker.totalSATScore)/1600 (Math: \(satTracker.currentMathScore) | RW: \(satTracker.currentRWScore)) • ExAcc: \(formatPoints(exAcc.totalStandardCharge)) ball • Gu No-Error: \(currentGuNoErrorScore)/20%"
    }

    private func migrateToV5_2Oct18SynergyIfNeeded() {
        if !settings.migratedV5_2Oct18TerminalBackup || tasks.isEmpty {
            _ = syncTodayScheduleAndScores(force: false)
            settings.migratedV3Oct16 = true
            settings.migratedV3_1BlueSpectrum = true
            settings.migratedV5_2Oct18TerminalBackup = true
            saveSettings()
        } else {
            // Even if already migrated, upgrade old generic Eslatmalar rules to the 3 RPA Anti-Habits if untouched
            if rules.first?.title.contains("Fokus vaqtida telefon") == true {
                self.rules = RuleItem.defaultRPARules
                saveRules()
            }
            if satTracker.totalSATScore < 791 {
                satTracker = SATTrackerState()
                saveSATTracker()
            }
            if exAcc.totalStandardCharge < 230 {
                exAcc.totalStandardCharge = 230
                saveExAcc()
            }
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
    public func saveRPAArchive() { atomicWriteJSON(rpaArchive, to: rpaArchiveFileURL) }
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
        // Never show inline toastBanner if window is collapsed into mini-bar, preventing any height expansion
        guard !settings.isNotesCollapsed else { return }
        self.toastBanner = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard let self = self else { return }
            if self.toastBanner == message {
                self.toastBanner = nil
                WindowController.shared.enforceCollapsedHeightIfNeeded()
            }
        }
    }

    // MARK: - RPA (Anti-Habit) Management

    public func addRule(title: String, type: RPARuleType = .dontRule, isLocked: Bool = false) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = RuleItem(title: trimmed, ruleType: type, isLocked: isLocked)
        rules.append(item)
        saveRules()
        autoRolloverAndArchiveRPADates()
        appendHistoryLine("- [RPA+] [{TIMESTAMP}] Yangi taqiqlangan odat qo'shildi: \(trimmed)")
    }

    public func updateRule(_ rule: RuleItem, newTitle: String, newType: RPARuleType) {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rules[idx].title = trimmed
        rules[idx].ruleType = newType
        saveRules()
        autoRolloverAndArchiveRPADates()
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
        autoRolloverAndArchiveRPADates()
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

    // MARK: - Copy Gemini Report (With 3-Day RPA Table & Gu No-Error 20% Synergy)

    public func copyGeminiSyncReportToClipboard() -> String {
        autoRolloverAndArchiveRPADates()
        let today = rpaTodayString
        let cols = rpaThreeDayColumns
        let completedToday = tasks.filter { $0.isCompleted }
        let overdueSAT = satTracker.topics.filter { $0.hasOverdueCheckpoint }
        let noErrorPct = currentGuNoErrorScore
        let yesterdayNoErrorPct = guNoErrorSectorScore(for: rpaYesterdayString)

        var report = """
        # 📊 FocusCorner Synergy Report (\(today))
        - **Umumiy SAT Balli:** \(satTracker.totalSATScore) / 1600 (Math: \(satTracker.currentMathScore) | RW: \(satTracker.currentRWScore))
        - **ExAcc Standart Zaryad:** \(formatPoints(exAcc.totalStandardCharge)) ball (Faol Acc: \(exAcc.activeMissionsCount)/2)
        - **Gu No-Error Sektori (RPA 20%):** \(noErrorPct) / 20% (Bugun: \(todayRPAXCount) ta X | Kecha: \(yesterdayRPAXCount) ta X -> \(yesterdayNoErrorPct)/20%)

        ## 🛡 RPA Jadvali (3 Kunlik Anti-Odat & Gu No-Error Nazorati):
        | Qilmaslik Kerak Bo'lgan Odat (RPA) | \(cols[0].title) (\(cols[0].shortDate)) | \(cols[1].title) (\(cols[1].shortDate)) | \(cols[2].title) (\(cols[2].shortDate)) |
        | :--- | :---: | :---: | :---: |
        """

        for rule in rules {
            let c0 = rule.isMarkedX(on: cols[0].dateString) ? "[ X ]" : "[ — ]"
            let c1 = rule.isMarkedX(on: cols[1].dateString) ? "[ X ]" : "[ — ]"
            let c2 = rule.isMarkedX(on: cols[2].dateString) ? "[ X ]" : "[ — ]"
            report += "\n| \(rule.title) | \(c0) | \(c1) | \(c2) |"
        }

        report += "\n\n## ✅ Bajarilgan Vazifalar:"
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
        showToast("📋 Gemini hisoboti (3-kunlik RPA + Gu No-Error bilan) buferga nusxalandi!")
        WindowController.shared.enforceCollapsedHeightIfNeeded()
        return report
    }

    private func startSafetyProtocolTimer() {
        protocolTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let nowToday = TaskItem.todayString()
                if nowToday != self.lastObservedTodayString {
                    self.lastObservedTodayString = nowToday
                    self.autoRolloverAndArchiveRPADates()
                    self.syncGuApertureNoErrorIfInstalled()
                }
                self.refreshSafetyProtocolStatus()
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