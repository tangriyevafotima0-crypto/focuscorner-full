import Foundation

public enum MissionTier: String, Codable, CaseIterable, Identifiable {
    case monumental = "Monumental"
    case substantial = "Substantial"
    case modest = "Modest"

    public var id: String { rawValue }
}

public enum AccType: String, Codable, CaseIterable, Identifiable {
    case nano = "Nano (<=3d)"
    case mini = "Mini (4-7d)"
    case midi = "Midi (8-30d)"
    case mani = "Mani (31-100d)"

    public var id: String { rawValue }

    public var isLongTerm: Bool {
        self == .midi || self == .mani
    }
}

public enum VolumeType: String, Codable, CaseIterable, Identifiable {
    case smooth = "Smooth"
    case peak = "Peak"
    case upper = "Upper"

    public var id: String { rawValue }
}

public struct ExAccMission: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var tier: MissionTier
    public var accType: AccType
    public var volume: VolumeType
    /// True if this mission is managed by an independent Faction skill (e.g. Score SAT System)
    /// Per ExAcc Faction Isolation Rule: ExAcc observes Faction missions in Read-Only mode and does NOT mix standard accumulator points into Faction scores.
    public var isFaction: Bool
    public var factionName: String?
    public var startDate: String
    public var deadlineDate: String
    public var nextCheckInDate: String
    public var earnedCharge: Double
    public var targetCharge: Double
    public var isAtRisk: Bool
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        tier: MissionTier = .substantial,
        accType: AccType = .midi,
        volume: VolumeType = .peak,
        isFaction: Bool = false,
        factionName: String? = nil,
        startDate: String = TaskItem.todayString(),
        deadlineDate: String = "2026-11-08",
        nextCheckInDate: String = TaskItem.todayString(),
        earnedCharge: Double = 0,
        targetCharge: Double = 500,
        isAtRisk: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.accType = accType
        self.volume = volume
        self.isFaction = isFaction
        self.factionName = factionName
        self.startDate = startDate
        self.deadlineDate = deadlineDate
        self.nextCheckInDate = nextCheckInDate
        self.earnedCharge = earnedCharge
        self.targetCharge = targetCharge
        self.isAtRisk = isAtRisk
        self.isActive = isActive
    }
}

public struct ExAccState: Codable, Equatable {
    public var totalStandardCharge: Double
    public var missions: [ExAccMission]
    public var lastAuditDate: String

    public init(
        totalStandardCharge: Double = 170,
        missions: [ExAccMission] = ExAccState.defaultMissions,
        lastAuditDate: String = TaskItem.todayString()
    ) {
        self.totalStandardCharge = totalStandardCharge
        self.missions = missions
        self.lastAuditDate = lastAuditDate
    }

    public static var defaultMissions: [ExAccMission] {
        [
            ExAccMission(
                title: "SAT 1500+ Master Plan (Faction: score-sat-system)",
                tier: .monumental,
                accType: .midi,
                volume: .peak,
                isFaction: true,
                factionName: "score-sat-system",
                startDate: "2026-10-10",
                deadlineDate: "2026-11-08",
                nextCheckInDate: "2026-10-16",
                earnedCharge: 654,
                targetCharge: 1550,
                isAtRisk: false,
                isActive: true
            ),
            ExAccMission(
                title: "FocusCorner v2 macOS Native Synergy App & Deep Work",
                tier: .modest,
                accType: .mini,
                volume: .peak,
                isFaction: false,
                factionName: nil,
                startDate: "2026-10-08",
                deadlineDate: "2026-10-18",
                nextCheckInDate: "2026-10-16",
                earnedCharge: 170,
                targetCharge: 250,
                isAtRisk: false,
                isActive: true
            )
        ]
    }

    public var activeMissionsCount: Int {
        missions.filter { $0.isActive }.count
    }

    public var isWIPLimitValid: Bool {
        let active = missions.filter { $0.isActive }
        let longCount = active.filter { $0.accType.isLongTerm }.count
        let shortCount = active.filter { !$0.accType.isLongTerm }.count
        return active.count <= 2 && longCount <= 1 && shortCount <= 1
    }
}

public struct SafetyProtocolMonitor {
    public static func currentStatus(now: Date = Date(), hasStartedHeavyTaskToday: Bool) -> (
        isHardStop: Bool,
        isHardStopApproaching: Bool,
        isSundayBuffer: Bool,
        isLaunchWindowWarning: Bool,
        statusBanner: String
    ) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday

        let isHardStop = (hour == 0 && minute >= 30) || (hour >= 1 && hour < 5)
        let isHardStopApproaching = (hour == 0 && minute < 30)
        let isSunday = (weekday == 1)
        let isLaunchWindowWarning = (hour == 13 && minute >= 30 || hour == 14 && minute <= 15) && !hasStartedHeavyTaskToday

        let banner: String
        if isHardStop {
            banner = "🛑 HARD STOP (00:30) FAOL — Uyqu vaqtiga daxl qilmang!"
        } else if isHardStopApproaching {
            banner = "⚠️ 00:30 Hard Stop yaqinlashmoqda — Ishlarni yakunlang!"
        } else if isSunday {
            banner = "🌴 SUNDAY BUFFER — 0 yangi akkumulyator, faqat haftalik audit va qoldiq tozalash!"
        } else if isLaunchWindowWarning {
            banner = "🚀 LAUNCH WINDOW (14:00) — Kunning birinchi og'ir vazifasini boshlang!"
        } else {
            banner = "⚡ ExAcc & Score SAT Protokollari Me'yorida"
        }

        return (isHardStop, isHardStopApproaching, isSunday, isLaunchWindowWarning, banner)
    }
}
