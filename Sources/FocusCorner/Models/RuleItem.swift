import Foundation

public enum RPARuleType: String, Codable, CaseIterable, Identifiable {
    case doRule = "DO"
    case dontRule = "DONT"
    case protocolRule = "PROTOCOL"

    public var id: String { rawValue }

    public var badgeText: String {
        switch self {
        case .doRule: return "DO ✅"
        case .dontRule: return "RPA 🚫"
        case .protocolRule: return "RPA ⚡"
        }
    }
}

public struct RPAArchivedDayEntry: Identifiable, Codable, Equatable {
    public var id: String { dateString }
    public var dateString: String
    public var violatedHabitTitles: [String]
    public var cleanHabitTitles: [String]
    public var totalHabitsCount: Int
    public var xCount: Int
    public var guNoErrorScore: Int
    public var archivedAt: String

    public init(
        dateString: String,
        violatedHabitTitles: [String],
        cleanHabitTitles: [String],
        totalHabitsCount: Int,
        xCount: Int,
        guNoErrorScore: Int,
        archivedAt: String
    ) {
        self.dateString = dateString
        self.violatedHabitTitles = violatedHabitTitles
        self.cleanHabitTitles = cleanHabitTitles
        self.totalHabitsCount = totalHabitsCount
        self.xCount = xCount
        self.guNoErrorScore = guNoErrorScore
        self.archivedAt = archivedAt
    }
}

public struct RuleItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var ruleType: RPARuleType
    public var isLocked: Bool
    public var createdAt: Date
    /// Sanalar ro'yxati ("yyyy-MM-dd") — foydalanuvchi ushbu sanada "X" bosgan (taqiqlangan odat sodir bo'lgan) kunlar
    public var xMarkedDates: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        ruleType: RPARuleType = .dontRule,
        isLocked: Bool = false,
        createdAt: Date = Date(),
        xMarkedDates: [String] = []
    ) {
        self.id = id
        self.title = title
        self.ruleType = ruleType
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.xMarkedDates = Array(Set(xMarkedDates)).sorted()
    }

    public func isMarkedX(on dateString: String) -> Bool {
        xMarkedDates.contains(dateString)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case ruleType
        case isLocked
        case createdAt
        case xMarkedDates
    }

    // Backward-compatible decoder: supports plain String, v1 RuleItem, v2 RuleItem, and v6.5 RPA RuleItem
    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let plainString = try? singleValue.decode(String.self) {
            self.id = UUID()
            self.title = plainString
            self.ruleType = .dontRule
            self.isLocked = false
            self.createdAt = Date()
            self.xMarkedDates = []
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        if let t = try? container.decode(String.self, forKey: .title) {
            self.title = t
        } else if let txt = try? container.decode(String.self, forKey: .text) {
            self.title = txt
        } else {
            self.title = "Taqiqlangan odat"
        }
        self.ruleType = (try? container.decode(RPARuleType.self, forKey: .ruleType)) ?? .dontRule
        self.isLocked = (try? container.decode(Bool.self, forKey: .isLocked)) ?? false
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        let rawDates = (try? container.decode([String].self, forKey: .xMarkedDates)) ?? []
        self.xMarkedDates = Array(Set(rawDates)).sorted()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(ruleType, forKey: .ruleType)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(xMarkedDates, forKey: .xMarkedDates)
    }

    /// Asosiy 3 ta qilmaslik kerak bo'lgan yomon odat (Gu Aptitude -> 20% No-Error Sektori indikatorlari)
    public static var defaultRPARules: [RuleItem] {
        [
            RuleItem(
                title: "Ijtimoiy tarmoq va behuda scrolling (No Social Media)",
                ruleType: .dontRule,
                isLocked: false
            ),
            RuleItem(
                title: "Kechki xayolparastlik va arzon dofamin (No Daydreaming)",
                ruleType: .dontRule,
                isLocked: false
            ),
            RuleItem(
                title: "00:30 dan keyin uyg'oq qolish / Rejani buzish (Hard Stop)",
                ruleType: .protocolRule,
                isLocked: false
            )
        ]
    }
}
