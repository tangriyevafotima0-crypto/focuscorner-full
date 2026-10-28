import Foundation

public enum RPARuleType: String, Codable, CaseIterable, Identifiable {
    case doRule = "DO"
    case dontRule = "DONT"
    case protocolRule = "PROTOCOL"

    public var id: String { rawValue }

    public var badgeText: String {
        switch self {
        case .doRule: return "DO ✅"
        case .dontRule: return "DON'T 🚫"
        case .protocolRule: return "RPA ⚡"
        }
    }
}

public struct RuleItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var ruleType: RPARuleType
    public var isLocked: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        ruleType: RPARuleType = .dontRule,
        isLocked: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.ruleType = ruleType
        self.isLocked = isLocked
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case text
        case ruleType
        case isLocked
        case createdAt
    }

    // Backward-compatible decoder: supports plain String ("No social media"), v1 RuleItem, and v2 RuleItem
    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let plainString = try? singleValue.decode(String.self) {
            self.id = UUID()
            self.title = plainString
            self.ruleType = plainString.lowercased().hasPrefix("no ") || plainString.lowercased().contains("taqiq") ? .dontRule : .doRule
            self.isLocked = true
            self.createdAt = Date()
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        if let t = try? container.decode(String.self, forKey: .title) {
            self.title = t
        } else if let txt = try? container.decode(String.self, forKey: .text) {
            self.title = txt
        } else {
            self.title = "Qoida"
        }
        self.ruleType = (try? container.decode(RPARuleType.self, forKey: .ruleType)) ?? .dontRule
        self.isLocked = (try? container.decode(Bool.self, forKey: .isLocked)) ?? false
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(ruleType, forKey: .ruleType)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public static var defaultRPARules: [RuleItem] {
        [
            RuleItem(title: "Fokus vaqtida telefon va ijtimoiy tarmoqlar yopiq turadi", ruleType: .dontRule, isLocked: false),
            RuleItem(title: "Bir vaqtda faqat 1 ta asosiy vazifaga diqqat qaratiladi", ruleType: .doRule, isLocked: false),
            RuleItem(title: "Har bir xatoni qisqacha konspektga yozib borish", ruleType: .doRule, isLocked: false),
            RuleItem(title: "00:30 dan keyin ish to'xtatiladi — uyqu muqaddas", ruleType: .protocolRule, isLocked: false)
        ]
    }
}
