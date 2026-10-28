import Foundation
import SwiftUI

public enum TaskSourceSystem: String, Codable, CaseIterable, Identifiable {
    case general = "GENERAL"
    case sat = "SAT"
    case exacc = "EXACC"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: return "Kunlik"
        case .sat: return "SAT"
        case .exacc: return "ExAcc"
        }
    }
}

public enum AccumulatorSize: String, Codable, CaseIterable, Identifiable {
    case none = "NONE"
    case small = "SMALL"
    case medium = "MEDIUM"
    case big = "BIG"

    public var id: String { rawValue }

    public var points: Double {
        switch self {
        case .none: return 0
        case .small: return 10
        case .medium: return 25
        case .big: return 50
        }
    }

    public var badgeLabel: String {
        switch self {
        case .none: return ""
        case .small: return "Small +10"
        case .medium: return "Med +25"
        case .big: return "Big +50"
        }
    }
}

public enum SATReviewStage: String, Codable, CaseIterable, Identifiable {
    case none = "NONE"
    case ingest = "INGEST"
    case day1 = "DAY_1"
    case day3 = "DAY_3"
    case day7 = "DAY_7"
    case day14 = "DAY_14"
    case day30 = "DAY_30"
    case fastTrack1 = "FAST_1"
    case fastTrack2 = "FAST_2"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .none: return ""
        case .ingest: return "Yangi mavzu"
        case .day1: return "Day 1"
        case .day3: return "Day 3"
        case .day7: return "Day 7"
        case .day14: return "Day 14"
        case .day30: return "Day 30"
        case .fastTrack1: return "Recovery 1"
        case .fastTrack2: return "Recovery 2"
        }
    }
}

/// Sokin va ko'zni charchatmaydigan 5 bosqichli rang tizimi:
/// 1. Bajarilganda (.completedGreen) -> Yashil ("Bajarildi • Yashil")
/// 2. 1 kun o'tib ketganda (.overdueRed) -> Qizil ("1 kun o'tib ketdi • Qizil")
/// 3. Bugun / 1 kun qolganda (.dueTodayBrightBlue) -> Ochiqroq ko'k ("Bugun • Ko'k")
/// 4. 3 kun qolganda (2-3 kun) (.threeDaysSkyCyan) -> Havorang ("3 kun qoldi • Havorang")
/// 5. Undan ko'prog'iga (4+ kun) (.moreDaysIceWhiteBlue) -> Ko'kish oq ("7 kun qoldi • Ko'kish oq")
public enum TaskVisualState: String, Codable, CaseIterable, Identifiable {
    case completedGreen = "COMPLETED_GREEN"
    case overdueRed = "OVERDUE_RED"
    case dueTodayBrightBlue = "DUE_TODAY_BRIGHT_BLUE"
    case threeDaysSkyCyan = "THREE_DAYS_SKY_CYAN"
    case moreDaysIceWhiteBlue = "MORE_DAYS_ICE_WHITE_BLUE"

    public var id: String { rawValue }

    public var accentColor: Color {
        switch self {
        case .completedGreen:
            return Color(red: 0.22, green: 0.84, blue: 0.52) // Calm Emerald Green
        case .overdueRed:
            return Color(red: 0.96, green: 0.40, blue: 0.44) // Soft Rose Red
        case .dueTodayBrightBlue:
            return Color(red: 0.30, green: 0.66, blue: 1.00) // Ochiqroq Ko'k (Smooth Azure)
        case .threeDaysSkyCyan:
            return Color(red: 0.36, green: 0.86, blue: 0.96) // Havorang (Soft Sky Cyan)
        case .moreDaysIceWhiteBlue:
            return Color(red: 0.84, green: 0.92, blue: 1.00) // Ko'kish Oq (Cool Ice White-Blue)
        }
    }

    public var subtleRowFill: Color {
        switch self {
        case .completedGreen:
            return Color(red: 0.16, green: 0.68, blue: 0.40).opacity(0.10)
        case .overdueRed:
            return Color(red: 0.85, green: 0.28, blue: 0.32).opacity(0.11)
        case .dueTodayBrightBlue:
            return Color(red: 0.22, green: 0.56, blue: 0.98).opacity(0.10)
        case .threeDaysSkyCyan:
            return Color(red: 0.25, green: 0.76, blue: 0.90).opacity(0.07)
        case .moreDaysIceWhiteBlue:
            return Color.white.opacity(0.045)
        }
    }

    public var subtleBorderStroke: Color {
        switch self {
        case .completedGreen:
            return Color(red: 0.22, green: 0.84, blue: 0.52).opacity(0.28)
        case .overdueRed:
            return Color(red: 0.96, green: 0.40, blue: 0.44).opacity(0.32)
        case .dueTodayBrightBlue:
            return Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.30)
        case .threeDaysSkyCyan:
            return Color(red: 0.36, green: 0.86, blue: 0.96).opacity(0.22)
        case .moreDaysIceWhiteBlue:
            return Color.white.opacity(0.10)
        }
    }
}

public struct TaskItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var sourceSystem: TaskSourceSystem
    public var accumulatorSize: AccumulatorSize
    public var satStage: SATReviewStage
    public var linkedEntityId: UUID?
    public var scheduledDate: String
    public var startDate: String
    public var durationDays: Int
    public var manualElapsedDaysOffset: Int
    public var pointsValue: Double
    public var notes: String

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sourceSystem: TaskSourceSystem = .general,
        accumulatorSize: AccumulatorSize = .none,
        satStage: SATReviewStage = .none,
        linkedEntityId: UUID? = nil,
        scheduledDate: String? = nil,
        startDate: String? = nil,
        durationDays: Int = 1,
        manualElapsedDaysOffset: Int = 0,
        pointsValue: Double = 0,
        notes: String = ""
    ) {
        let today = Self.todayString()
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sourceSystem = sourceSystem
        self.accumulatorSize = accumulatorSize
        self.satStage = satStage
        self.linkedEntityId = linkedEntityId
        self.scheduledDate = scheduledDate ?? today
        self.startDate = startDate ?? today
        self.durationDays = max(1, min(90, durationDays))
        self.manualElapsedDaysOffset = manualElapsedDaysOffset
        self.pointsValue = pointsValue
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, completed, createdAt, completedAt
        case sourceSystem, accumulatorSize, satStage, linkedEntityId
        case scheduledDate, startDate, durationDays, manualElapsedDaysOffset
        case pointsValue, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let today = Self.todayString()
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? container.decode(String.self, forKey: .title)) ?? "Vazifa"
        if let comp = try? container.decode(Bool.self, forKey: .isCompleted) {
            self.isCompleted = comp
        } else if let compLegacy = try? container.decode(Bool.self, forKey: .completed) {
            self.isCompleted = compLegacy
        } else {
            self.isCompleted = false
        }
        let created = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.createdAt = created
        self.completedAt = try? container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.sourceSystem = (try? container.decode(TaskSourceSystem.self, forKey: .sourceSystem)) ?? .general
        self.accumulatorSize = (try? container.decode(AccumulatorSize.self, forKey: .accumulatorSize)) ?? .none
        self.satStage = (try? container.decode(SATReviewStage.self, forKey: .satStage)) ?? .none
        self.linkedEntityId = try? container.decodeIfPresent(UUID.self, forKey: .linkedEntityId)
        let sched = (try? container.decode(String.self, forKey: .scheduledDate)) ?? today
        self.scheduledDate = sched
        self.startDate = (try? container.decode(String.self, forKey: .startDate)) ?? Self.todayString(from: created)
        if let dur = try? container.decode(Int.self, forKey: .durationDays) {
            self.durationDays = max(1, min(90, dur))
        } else {
            let diff = Self.daysBetween(from: today, to: sched)
            self.durationDays = diff > 0 ? max(1, diff + 1) : 1
        }
        self.manualElapsedDaysOffset = (try? container.decode(Int.self, forKey: .manualElapsedDaysOffset)) ?? 0
        self.pointsValue = (try? container.decode(Double.self, forKey: .pointsValue)) ?? 0
        self.notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(sourceSystem, forKey: .sourceSystem)
        try container.encode(accumulatorSize, forKey: .accumulatorSize)
        try container.encode(satStage, forKey: .satStage)
        try container.encodeIfPresent(linkedEntityId, forKey: .linkedEntityId)
        try container.encode(scheduledDate, forKey: .scheduledDate)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(durationDays, forKey: .durationDays)
        try container.encode(manualElapsedDaysOffset, forKey: .manualElapsedDaysOffset)
        try container.encode(pointsValue, forKey: .pointsValue)
        try container.encode(notes, forKey: .notes)
    }

    /// Clean, human-readable title without technical bracket noise
    public var cleanDisplayTitle: String {
        var t = title
        let prefixes = ["[SAT Math] ", "[SAT English] ", "[SAT SR] ", "[ExAcc] ", "[SAT] "]
        for p in prefixes {
            t = t.replacingOccurrences(of: p, with: "")
        }
        t = t.replacingOccurrences(of: " — Deep Focus (Ingest 30%)", with: "")
        t = t.replacingOccurrences(of: " — Sunday Buffer (Ingest 30%)", with: " (Yakshanba)")
        t = t.replacingOccurrences(of: " (Ingest 30%)", with: "")
        return t
    }

    public static func todayString(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    public static func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: str)
    }

    public static func daysBetween(from startStr: String, to endStr: String) -> Int {
        guard let d1 = parseDate(startStr), let d2 = parseDate(endStr) else { return 0 }
        let cal = Calendar.current
        let c1 = cal.startOfDay(for: d1)
        let c2 = cal.startOfDay(for: d2)
        return cal.dateComponents([.day], from: c1, to: c2).day ?? 0
    }

    public var elapsedDays: Int {
        let calDiff = Self.daysBetween(from: startDate, to: Self.todayString())
        return calDiff + manualElapsedDaysOffset
    }

    public var remainingDays: Int {
        return durationDays - elapsedDays
    }

    public var overdueDaysCount: Int {
        let rem = remainingDays
        return rem <= 0 ? abs(rem) + 1 : 0
    }

    public var visualState: TaskVisualState {
        if isCompleted {
            return .completedGreen
        }
        let rem = remainingDays
        if rem <= 0 {
            return .overdueRed
        } else if rem == 1 {
            return .dueTodayBrightBlue
        } else if rem <= 3 {
            return .threeDaysSkyCyan
        } else {
            return .moreDaysIceWhiteBlue
        }
    }

    /// Vazifa pastki qismida ko'rinadigan silliq va tushunarli yozuv
    public var bottomStatusBadgeText: String {
        if isCompleted {
            return "Bajarildi • Yashil"
        }
        let rem = remainingDays
        if rem <= 0 {
            return "\(overdueDaysCount) kun o'tib ketdi • Qizil"
        } else if rem == 1 {
            return durationDays == 1 ? "Bugun • Ko'k" : "1 kun qoldi (Bugun) • Ko'k"
        } else if rem <= 3 {
            return "\(rem) kun qoldi • Havorang"
        } else {
            return "\(rem) kun qoldi • Ko'kish oq"
        }
    }

    public var isOverdue: Bool {
        guard !isCompleted else { return false }
        return remainingDays <= 0
    }

    public var isToday: Bool {
        return remainingDays == 1 || scheduledDate == Self.todayString()
    }

    public var isFuture: Bool {
        return remainingDays > 1 && scheduledDate > Self.todayString()
    }
}
