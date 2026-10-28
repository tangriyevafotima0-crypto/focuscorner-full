import Foundation
import SwiftUI

public enum NotebookCategory: String, Codable, CaseIterable, Identifiable {
    case insights = "INSIGHTS"
    case quickCapture = "QUICK_CAPTURE"
    case journal = "JOURNAL"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .insights: return "Insightlar"
        case .quickCapture: return "Eslab qolish"
        case .journal: return "Journaling"
        }
    }

    public var subtitleHint: String {
        switch self {
        case .insights: return "Tushunib yetgan foydali fikrlar va kashfiyotlar (⌘1)"
        case .quickCapture: return "Ko'chada aytilgan gaplar va esdan chiqmasligi kerak qaydlar (⌘2)"
        case .journal: return "Falsafiy g'oyalar, iqtiboslar va shaxsiy kundalik (⌘3)"
        }
    }

    public var iconName: String {
        switch self {
        case .insights: return "lightbulb.fill"
        case .quickCapture: return "pin.fill"
        case .journal: return "book.closed.fill"
        }
    }

    public var folderName: String {
        switch self {
        case .insights: return "1_Insights"
        case .quickCapture: return "2_Eslab_Qolish"
        case .journal: return "3_Journaling"
        }
    }

    public var accentColor: Color {
        switch self {
        case .insights: return Color(red: 0.98, green: 0.78, blue: 0.28) // Warm Gold
        case .quickCapture: return Color(red: 0.32, green: 0.68, blue: 1.00) // Crisp Azure
        case .journal: return Color(red: 0.68, green: 0.52, blue: 0.98) // Calm Lavender
        }
    }
}

public enum NotebookAttachmentKind: String, Codable {
    case image = "IMAGE"
    case audio = "AUDIO"
    case link = "LINK"
}

public struct NotebookAttachment: Identifiable, Codable, Equatable {
    public var id: UUID
    public var kind: NotebookAttachmentKind
    public var title: String
    public var relativeFilePath: String // Relative to category directory or full URL for links
    public var createdAt: String

    public init(
        id: UUID = UUID(),
        kind: NotebookAttachmentKind,
        title: String,
        relativeFilePath: String,
        createdAt: String = TaskItem.todayString()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.relativeFilePath = relativeFilePath
        self.createdAt = createdAt
    }
}

public struct NotebookPageManifest: Codable, Equatable {
    public var pageId: String
    public var title: String
    public var category: NotebookCategory
    public var createdAt: String
    public var updatedAt: String
    public var rtfFileName: String
    public var attachments: [NotebookAttachment]

    public init(
        pageId: String = "active_main",
        title: String = "Asosiy Daftar",
        category: NotebookCategory,
        createdAt: String = TaskItem.todayString(),
        updatedAt: String = TaskItem.todayString(),
        rtfFileName: String = "active_main.rtf",
        attachments: [NotebookAttachment] = []
    ) {
        self.pageId = pageId
        self.title = title
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rtfFileName = rtfFileName
        self.attachments = attachments
    }
}

public enum NoteHighlightColor: String, CaseIterable, Identifiable {
    case skyBlue = "Ko'k"
    case goldYellow = "Sariq"
    case emeraldGreen = "Yashil"
    case coralRed = "Qizil"
    case lavender = "Binafsha"
    case pureWhite = "Oq (Standart)"

    public var id: String { rawValue }

    public var nsColor: NSColor {
        switch self {
        case .skyBlue: return NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.00, alpha: 1.0)
        case .goldYellow: return NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.32, alpha: 1.0)
        case .emeraldGreen: return NSColor(calibratedRed: 0.28, green: 0.90, blue: 0.56, alpha: 1.0)
        case .coralRed: return NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.48, alpha: 1.0)
        case .lavender: return NSColor(calibratedRed: 0.76, green: 0.60, blue: 1.00, alpha: 1.0)
        case .pureWhite: return NSColor(calibratedWhite: 0.94, alpha: 1.0)
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .skyBlue: return Color(red: 0.35, green: 0.75, blue: 1.00)
        case .goldYellow: return Color(red: 1.00, green: 0.84, blue: 0.32)
        case .emeraldGreen: return Color(red: 0.28, green: 0.90, blue: 0.56)
        case .coralRed: return Color(red: 1.00, green: 0.45, blue: 0.48)
        case .lavender: return Color(red: 0.76, green: 0.60, blue: 1.00)
        case .pureWhite: return Color.white.opacity(0.92)
        }
    }
}
