import Foundation
import AppKit

public enum CornerPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topLeft: return "Yuqori Chap (↖)"
        case .topRight: return "Yuqori O'ng (↗)"
        case .bottomLeft: return "Pastki Chap (↙)"
        case .bottomRight: return "Pastki O'ng (↘)"
        }
    }

    public var shortIcon: String {
        switch self {
        case .topLeft: return "arrow.up.left.square"
        case .topRight: return "arrow.up.right.square"
        case .bottomLeft: return "arrow.down.left.square"
        case .bottomRight: return "arrow.down.right.square"
        }
    }
}

public enum HUDSizePreset: String, Codable, CaseIterable, Identifiable {
    case compact = "S"
    case standard = "M"
    case expanded = "L"

    public var id: String { rawValue }

    public var rulesDimensions: NSSize {
        switch self {
        case .compact: return NSSize(width: 260, height: 220)
        case .standard: return NSSize(width: 310, height: 310)
        case .expanded: return NSSize(width: 380, height: 420)
        }
    }

    public var notesDimensions: NSSize {
        switch self {
        case .compact: return NSSize(width: 340, height: 360)
        case .standard: return NSSize(width: 420, height: 500)
        case .expanded: return NSSize(width: 520, height: 640)
        }
    }
}

public enum WindowLayerLevel: String, Codable, CaseIterable, Identifiable {
    case floating = "floating"
    case statusBar = "statusBar"
    case maximum = "maximum"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .floating: return "Standart Ustki (.floating)"
        case .statusBar: return "Full-Screen Ustida (.statusBar)"
        case .maximum: return "Maksimal Qatlam (Always-On-Top)"
        }
    }

    public var nsWindowLevel: NSWindow.Level {
        switch self {
        case .floating:
            return .floating
        case .statusBar:
            return .statusBar
        case .maximum:
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        }
    }
}
