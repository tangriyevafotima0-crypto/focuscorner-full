import Foundation
import SwiftUI

public enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case singular = "SINGULAR"
    case exam = "EXAM"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singular: return "Singular (Doimiy)"
        case .exam: return "Exam (Partlangan)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .singular: return "SINGULAR"
        case .exam: return "EXAM"
        }
    }
}

public enum TimerPartKind: String, Codable, CaseIterable, Identifiable {
    case work = "WORK"
    case rest = "REST"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .work: return "🎯 Ish / Fokus"
        case .rest: return "☕ Dam olish"
        }
    }

    public var shortLabel: String {
        switch self {
        case .work: return "Fokus"
        case .rest: return "Dam"
        }
    }
}

public struct TimerPart: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var durationMinutes: Int
    public var kind: TimerPartKind

    public init(
        id: UUID = UUID(),
        title: String,
        durationMinutes: Int,
        kind: TimerPartKind = .work
    ) {
        self.id = id
        self.title = title
        self.durationMinutes = max(1, min(300, durationMinutes))
        self.kind = kind
    }
}

public enum ExamTemplatePreset: String, CaseIterable, Identifiable {
    case classic60_10_45 = "Klassik (60m Ish • 10m Dam • 45m Ish)"
    case satBluebook = "SAT Bluebook (32m • 32m • 10m Dam • 35m • 35m)"
    case deepSprint50_10_50 = "Chuqur Sprint (50m Ish • 10m Dam • 50m Ish)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .classic60_10_45: return "60 / 10 / 45 (Klassik)"
        case .satBluebook: return "SAT Exam (Bluebook)"
        case .deepSprint50_10_50: return "50 / 10 / 50 (Sprint)"
        }
    }

    public var parts: [TimerPart] {
        switch self {
        case .classic60_10_45:
            return [
                TimerPart(title: "1-Part: Asosiy Chuqur Ish", durationMinutes: 60, kind: .work),
                TimerPart(title: "2-Part: Dam olish va Tiklanish", durationMinutes: 10, kind: .rest),
                TimerPart(title: "3-Part: Ikkinchi Fokus Bloki", durationMinutes: 45, kind: .work)
            ]
        case .satBluebook:
            return [
                TimerPart(title: "1-Part: Reading & Writing Mod 1", durationMinutes: 32, kind: .work),
                TimerPart(title: "2-Part: Reading & Writing Mod 2", durationMinutes: 32, kind: .work),
                TimerPart(title: "3-Part: Rasmiy Tanaffus (Break)", durationMinutes: 10, kind: .rest),
                TimerPart(title: "4-Part: Math Module 1", durationMinutes: 35, kind: .work),
                TimerPart(title: "5-Part: Math Module 2", durationMinutes: 35, kind: .work)
            ]
        case .deepSprint50_10_50:
            return [
                TimerPart(title: "1-Part: 1-Fokus Sprint", durationMinutes: 50, kind: .work),
                TimerPart(title: "2-Part: Qisqa Dam olish", durationMinutes: 10, kind: .rest),
                TimerPart(title: "3-Part: 2-Fokus Sprint", durationMinutes: 50, kind: .work)
            ]
        }
    }
}

public struct TimerConfiguration: Codable, Equatable {
    public var mode: TimerMode
    public var singularMinutes: Int
    public var examParts: [TimerPart]
    public var hideTasksWhenTimerStarts: Bool
    public var adaptiveRPAWhenTimerStarts: Bool
    public var autoAdvanceExamParts: Bool
    public var timerOriginX: Double?
    public var timerOriginY: Double?

    public init(
        mode: TimerMode = .exam,
        singularMinutes: Int = 45,
        examParts: [TimerPart] = ExamTemplatePreset.classic60_10_45.parts,
        hideTasksWhenTimerStarts: Bool = true,
        adaptiveRPAWhenTimerStarts: Bool = true,
        autoAdvanceExamParts: Bool = true,
        timerOriginX: Double? = nil,
        timerOriginY: Double? = nil
    ) {
        self.mode = mode
        self.singularMinutes = max(1, min(300, singularMinutes))
        self.examParts = examParts.isEmpty ? ExamTemplatePreset.classic60_10_45.parts : examParts
        self.hideTasksWhenTimerStarts = hideTasksWhenTimerStarts
        self.adaptiveRPAWhenTimerStarts = adaptiveRPAWhenTimerStarts
        self.autoAdvanceExamParts = autoAdvanceExamParts
        self.timerOriginX = timerOriginX
        self.timerOriginY = timerOriginY
    }
}
