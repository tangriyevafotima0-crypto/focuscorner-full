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
    public var dueDate: String // "YYYY-MM-DD"
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
        systemVersion: String = "SSS v3.0 (1-3-7-14-30 Verified)",
        baseMathScore: Double = 200,
        baseRWScore: Double = 200,
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

    // Pre-populated with the user's exact 556 / 1600 progress (Math: 279, R&W: 277) as of Oct 16, 2026
    public static var initialUserTopics: [SATTopic] {
        [
            SATTopic(
                title: "Linear Functions & Systems",
                section: .math,
                category: .kat1,
                potentialWeight: 80,
                currentScore: 56,
                learnedDate: "2026-10-10",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-11", pointsDelta: 16, isCompleted: true, completedDate: "2026-10-11"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-13", pointsDelta: 16, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-17", pointsDelta: 0, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-24", pointsDelta: 12, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-09", pointsDelta: 12, isCompleted: false)
                ],
                trapsAndNotes: "Sign trap: 3 - (-1) = 4; Standart ko'rinishda y ni yolg'iz qoldirish; Perpendikulyar -1/m; No Solution vs Infinitely Many."
            ),
            SATTopic(
                title: "Transitions (Logical Connectors)",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 49,
                learnedDate: "2026-10-11",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-12", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-12"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-14", pointsDelta: 14, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-18", pointsDelta: 0, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-25", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-10", pointsDelta: 10.5, isCompleted: false)
                ],
                trapsAndNotes: "Contrast vs Cause/Effect vs Addition. Oldingi va keyingi gap mantiqini bog'lovchisiz o'qib ko'rish."
            ),
            SATTopic(
                title: "Subject-Verb Agreement & Pronouns",
                section: .readingWriting,
                category: .kat2,
                potentialWeight: 40,
                currentScore: 28,
                learnedDate: "2026-10-12",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-13", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-15", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-16"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-19", pointsDelta: 0, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-26", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-11", pointsDelta: 6, isCompleted: false)
                ],
                trapsAndNotes: "Prepositional phrases (of/in/with...) ega bo'la olmaydi; Singular vs Plural pronoun antecedent."
            ),
            SATTopic(
                title: "Ratios, Rates, Percentages & Unit Conversions",
                section: .math,
                category: .kat2,
                potentialWeight: 50,
                currentScore: 23,
                learnedDate: "2026-10-13",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-14", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-16", pointsDelta: 8, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-20", pointsDelta: 0, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-27", pointsDelta: 7, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-12", pointsDelta: 7, isCompleted: false)
                ],
                trapsAndNotes: "Multiplier method (1.25, 0.85); Maydon/hajm birliklarida kvadrat/kub; O'rtacha tezlik = Jami masofa / Jami vaqt."
            )
        ]
    }
}
