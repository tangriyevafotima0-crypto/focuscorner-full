import Foundation

public enum SATSection: String, Codable, CaseIterable, Identifiable {
    case math = "SAT Math"
    case readingWriting = "SAT Reading & Writing"

    public var id: String { rawValue }
}

public enum SATCategory: String, Codable, CaseIterable, Identifiable {
    case kat1 = "Kat-1 (High-Yield Deep Focus)"
    case kat2 = "Kat-2 (Standard)"

    public var id: String { rawValue }
}

public enum SATTopicStatus: String, Codable {
    case notStarted = "Boshlanmagan (0%)"
    case ingested = "Ingested (30%)"
    case refined50 = "Refined (50%)"
    case refined70 = "Refined (70%)"
    case consolidated85 = "Consolidated (85%)"
    case mastered100 = "MASTERED (100%)"
    case vulnerable = "VULNERABLE (Mock Penalty -30%)"
    case burned = "BURNED (0% - Qayta o'rganish)"
}

public struct SATReviewCheckpoint: Identifiable, Codable, Equatable {
    public var id: UUID
    public var stage: SATReviewStage
    public var dueDate: String
    public var pointsDelta: Double
    public var isCompleted: Bool
    public var completedDate: String?

    public init(
        id: UUID = UUID(),
        stage: SATReviewStage,
        dueDate: String,
        pointsDelta: Double,
        isCompleted: Bool = false,
        completedDate: String? = nil
    ) {
        self.id = id
        self.stage = stage
        self.dueDate = dueDate
        self.pointsDelta = pointsDelta
        self.isCompleted = isCompleted
        self.completedDate = completedDate
    }
}

public struct SATTopic: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var section: SATSection
    public var category: SATCategory
    public var potentialWeight: Double
    public var currentScore: Double
    public var learnedDate: String
    public var status: SATTopicStatus
    public var checkpoints: [SATReviewCheckpoint]
    public var trapsAndNotes: String

    public init(
        id: UUID = UUID(),
        title: String,
        section: SATSection,
        category: SATCategory,
        potentialWeight: Double,
        currentScore: Double,
        learnedDate: String,
        status: SATTopicStatus,
        checkpoints: [SATReviewCheckpoint],
        trapsAndNotes: String = ""
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.category = category
        self.potentialWeight = potentialWeight
        self.currentScore = currentScore
        self.learnedDate = learnedDate
        self.status = status
        self.checkpoints = checkpoints
        self.trapsAndNotes = trapsAndNotes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case section
        case category
        case potentialWeight
        case currentScore
        case learnedDate
        case status
        case checkpoints
        case trapsAndNotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        if let t = try? container.decode(String.self, forKey: .title) {
            self.title = t
        } else if let n = try? container.decode(String.self, forKey: .name) {
            self.title = n
        } else {
            self.title = "SAT Mavzu"
        }
        self.section = (try? container.decode(SATSection.self, forKey: .section)) ?? .math
        self.category = (try? container.decode(SATCategory.self, forKey: .category)) ?? .kat1
        self.potentialWeight = (try? container.decode(Double.self, forKey: .potentialWeight)) ?? 70.0
        self.currentScore = (try? container.decode(Double.self, forKey: .currentScore)) ?? 0.0
        self.learnedDate = (try? container.decode(String.self, forKey: .learnedDate)) ?? "2026-10-21"
        self.status = (try? container.decode(SATTopicStatus.self, forKey: .status)) ?? .ingested
        self.checkpoints = (try? container.decode([SATReviewCheckpoint].self, forKey: .checkpoints)) ?? []
        self.trapsAndNotes = (try? container.decode(String.self, forKey: .trapsAndNotes)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(section, forKey: .section)
        try container.encode(category, forKey: .category)
        try container.encode(potentialWeight, forKey: .potentialWeight)
        try container.encode(currentScore, forKey: .currentScore)
        try container.encode(learnedDate, forKey: .learnedDate)
        try container.encode(status, forKey: .status)
        try container.encode(checkpoints, forKey: .checkpoints)
        try container.encode(trapsAndNotes, forKey: .trapsAndNotes)
    }

    public var masteryPercentage: Int {
        guard potentialWeight > 0 else { return 0 }
        return Int(round((currentScore / potentialWeight) * 100.0))
    }

    public var hasOverdueCheckpoint: Bool {
        let today = TaskItem.todayString()
        return checkpoints.contains { !$0.isCompleted && $0.dueDate < today }
    }

    public var nextPendingCheckpoint: SATReviewCheckpoint? {
        checkpoints.first { !$0.isCompleted }
    }
}

public struct SATTrackerState: Codable, Equatable {
    public var systemVersion: String
    public var baseMathScore: Double
    public var baseRWScore: Double
    public var topics: [SATTopic]

    public init(
        systemVersion: String = "SSS v6.5 (1-3-7-14-30 Verified • Oct 22)",
        baseMathScore: Double = 208,
        baseRWScore: Double = 233.5,
        topics: [SATTopic] = SATTrackerState.initialUserTopics
    ) {
        self.systemVersion = systemVersion
        self.baseMathScore = baseMathScore
        self.baseRWScore = baseRWScore
        self.topics = topics
    }

    public var currentMathScore: Int {
        let gained = topics
            .filter { $0.section == .math }
            .reduce(0.0) { $0 + $1.currentScore }
        return min(800, Int(round(baseMathScore + gained)))
    }

    public var currentRWScore: Int {
        let gained = topics
            .filter { $0.section == .readingWriting }
            .reduce(0.0) { $0 + $1.currentScore }
        return min(800, Int(round(baseRWScore + gained)))
    }

    public var totalSATScore: Int {
        currentMathScore + currentRWScore
    }

    /// Pre-populated with exact 791 / 1600 progress (Math: 345, R&W: 446) as of Oct 21-22, 2026:
    /// Math: 208 (Base+Drill) + 68 (Linear Functions) + 37 (Ratios Day 7) + 32 (Linear Inequalities Day 1) = 345
    /// R&W: 233.5 (Base+Conventions) + 59.5 (Transitions) + 34 (Subject-Verb Day 7) + 43 (Words in Context Day 3) + 35 (Boundaries Day 1) + 20 (Verb Tense Day 1) + 21 (Command of Evidence Ingest) = 446
    public static var initialUserTopics: [SATTopic] {
        [
            SATTopic(
                title: "Linear Functions & Systems",
                section: .math,
                category: .kat1,
                potentialWeight: 80,
                currentScore: 68,
                learnedDate: "2026-10-10",
                status: .consolidated85,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-11", pointsDelta: 16, isCompleted: true, completedDate: "2026-10-11"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-13", pointsDelta: 16, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-17", pointsDelta: 12, isCompleted: true, completedDate: "2026-10-18"),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-24", pointsDelta: 12, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-09", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Sign trap: 3 - (-1) = 4; Standart ko'rinishda y ni yolg'iz qoldirish; Perpendikulyar -1/m."
            ),
            SATTopic(
                title: "Ratios, Rates, Percentages & Unit Conversions",
                section: .math,
                category: .kat2,
                potentialWeight: 50,
                currentScore: 37,
                learnedDate: "2026-10-13",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-14", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-16", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-16"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-20", pointsDelta: 6, isCompleted: true, completedDate: "2026-10-20"),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-27", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-12", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Multiplier method (1.25, 0.85); Maydon/hajm birliklarida kvadrat/kub."
            ),
            SATTopic(
                title: "Linear Inequalities & Word Problems",
                section: .math,
                category: .kat2,
                potentialWeight: 50,
                currentScore: 32,
                learnedDate: "2026-10-19",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-20", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-20"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-22", pointsDelta: 8, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-26", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-11-02", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-18", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Manfiy songa ko'paytirish/bo'lishda ishora o'zgarishi; at least (>=) vs at most (<=)."
            ),
            SATTopic(
                title: "Transitions (Logical Connectors)",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 59.5,
                learnedDate: "2026-10-11",
                status: .consolidated85,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-12", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-12"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-14", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-18", pointsDelta: 10.5, isCompleted: true, completedDate: "2026-10-18"),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-25", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-10", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Contrast vs Cause/Effect vs Addition."
            ),
            SATTopic(
                title: "Subject-Verb Agreement & Pronouns",
                section: .readingWriting,
                category: .kat2,
                potentialWeight: 40,
                currentScore: 34,
                learnedDate: "2026-10-12",
                status: .consolidated85,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-13", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-15", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-16"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-19", pointsDelta: 6, isCompleted: true, completedDate: "2026-10-19"),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-26", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-11", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Prepositional phrases (of/in/with...) ega bo'la olmaydi."
            ),
            SATTopic(
                title: "Words in Context",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 43,
                learnedDate: "2026-10-16",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-17", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-18"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-19", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-19"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-23", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-30", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-15", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Context clue charge (+/-), Semantik juftlik va Contrast signal so'zlar."
            ),
            SATTopic(
                title: "Boundaries & Punctuation",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 35,
                learnedDate: "2026-10-19",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-20", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-20"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-22", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-26", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-11-02", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-18", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Semicolons, Colons, Dashes, Comma Splice tuzoqlari."
            ),
            SATTopic(
                title: "Verb Tense, Modifiers & Parallelism",
                section: .readingWriting,
                category: .kat2,
                potentialWeight: 40,
                currentScore: 20,
                learnedDate: "2026-10-20",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-21", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-21"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-23", pointsDelta: 8, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-27", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-11-03", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-19", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Dangling modifier: verguldan keyin darhol haqiqiy ega kelishi shart."
            ),
            SATTopic(
                title: "Command of Evidence",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 21,
                learnedDate: "2026-10-21",
                status: .ingested,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-22", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-24", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-28", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-11-04", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-20", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Quantitative & Textual Evidence: grafik va da'vo 100% mos kelishi."
            )
        ]
    }
}
