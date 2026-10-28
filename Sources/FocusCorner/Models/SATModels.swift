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
        systemVersion: String = "SSS v5.2 (1-3-7-14-30 Verified • Oct 18)",
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

    /// Pre-populated with exact 654 / 1600 progress (Math: 307, R&W: 347) as of Oct 18, 2026:
    /// Math: 200 + 68 (Linear Functions Day 7 done) + 31 (Ratios Day 3 done) + 8 (Exponential base) = 307
    /// R&W: 200 + 49 (Transitions) + 28 (Subject-Verb) + 29 (Words in Context Day 1 done) + 41 (Central Ideas & Command of Evidence) = 347
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
                trapsAndNotes: "Sign trap: 3 - (-1) = 4; Standart ko'rinishda y ni yolg'iz qoldirish; Perpendikulyar -1/m; No Solution vs Infinitely Many."
            ),
            SATTopic(
                title: "Ratios, Rates, Percentages & Unit Conversions",
                section: .math,
                category: .kat2,
                potentialWeight: 50,
                currentScore: 31,
                learnedDate: "2026-10-13",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-14", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-14"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-16", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-16"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-20", pointsDelta: 0, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-27", pointsDelta: 7, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-12", pointsDelta: 7, isCompleted: false)
                ],
                trapsAndNotes: "Multiplier method (1.25, 0.85); Maydon/hajm birliklarida kvadrat/kub; O'rtacha tezlik = Jami masofa / Jami vaqt."
            ),
            SATTopic(
                title: "Exponential Functions & Growth/Decay",
                section: .math,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 8,
                learnedDate: "2026-10-17",
                status: .ingested,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-18", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-20", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-24", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-31", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-16", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "f(t) = a(1 + r)^(t/k); y-intercept boshlang'ich qiymat a; har k vaqt oralig'ida o'zgarish."
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
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-18", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-25", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-10", pointsDelta: 0, isCompleted: false)
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
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-19", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-26", pointsDelta: 6, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-11", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Prepositional phrases (of/in/with...) ega bo'la olmaydi; Singular vs Plural pronoun antecedent."
            ),
            SATTopic(
                title: "Words in Context",
                section: .readingWriting,
                category: .kat1,
                potentialWeight: 70,
                currentScore: 29,
                learnedDate: "2026-10-16",
                status: .refined50,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-17", pointsDelta: 8, isCompleted: true, completedDate: "2026-10-18"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-19", pointsDelta: 14, isCompleted: false),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-23", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-30", pointsDelta: 10.5, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-15", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Context clue charge (+/-), Semantik juftlik va Contrast signal so'zlar."
            ),
            SATTopic(
                title: "Central Ideas & Command of Evidence",
                section: .readingWriting,
                category: .kat2,
                potentialWeight: 60,
                currentScore: 41,
                learnedDate: "2026-10-14",
                status: .refined70,
                checkpoints: [
                    SATReviewCheckpoint(stage: .day1, dueDate: "2026-10-15", pointsDelta: 12, isCompleted: true, completedDate: "2026-10-15"),
                    SATReviewCheckpoint(stage: .day3, dueDate: "2026-10-17", pointsDelta: 11, isCompleted: true, completedDate: "2026-10-17"),
                    SATReviewCheckpoint(stage: .day7, dueDate: "2026-10-21", pointsDelta: 9, isCompleted: false),
                    SATReviewCheckpoint(stage: .day14, dueDate: "2026-10-28", pointsDelta: 9, isCompleted: false),
                    SATReviewCheckpoint(stage: .day30, dueDate: "2026-11-13", pointsDelta: 0, isCompleted: false)
                ],
                trapsAndNotes: "Too broad vs Too narrow javob tuzoqlari; faqat matnda bevosita isbotlangan dalil."
            )
        ]
    }
}
