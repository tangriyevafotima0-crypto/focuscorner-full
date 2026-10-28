import Foundation
import AppKit

public struct AppSettings: Codable, Equatable {
    public var pinnedCorner: CornerPosition
    public var isRulesPinned: Bool
    public var lastPromptDate: String
    public var windowLevel: WindowLayerLevel
    public var rulesWidth: Double
    public var rulesHeight: Double
    public var rulesOriginX: Double?
    public var rulesOriginY: Double?
    public var notesWidth: Double
    public var notesHeight: Double
    public var notesOriginX: Double?
    public var notesOriginY: Double?
    public var rulesOpacity: Double
    public var notesOpacity: Double
    public var isRulesCollapsed: Bool
    public var isNotesCollapsed: Bool
    public var isGhostClickThrough: Bool
    public var fontScale: Double
    public var updateChannel: String
    public var allowEarlyFutureSATReviews: Bool
    public var migratedV3Oct16: Bool
    public var migratedV3_1BlueSpectrum: Bool

    public init(
        pinnedCorner: CornerPosition = .bottomRight,
        isRulesPinned: Bool = false,
        lastPromptDate: String = "",
        windowLevel: WindowLayerLevel = .statusBar,
        rulesWidth: Double = 300,
        rulesHeight: Double = 220,
        rulesOriginX: Double? = nil,
        rulesOriginY: Double? = nil,
        notesWidth: Double = 440,
        notesHeight: Double = 530,
        notesOriginX: Double? = nil,
        notesOriginY: Double? = nil,
        rulesOpacity: Double = 0.96,
        notesOpacity: Double = 0.96,
        isRulesCollapsed: Bool = false,
        isNotesCollapsed: Bool = false,
        isGhostClickThrough: Bool = false,
        fontScale: Double = 1.0,
        updateChannel: String = "release",
        allowEarlyFutureSATReviews: Bool = false,
        migratedV3Oct16: Bool = false,
        migratedV3_1BlueSpectrum: Bool = false
    ) {
        self.pinnedCorner = pinnedCorner
        self.isRulesPinned = isRulesPinned
        self.lastPromptDate = lastPromptDate
        self.windowLevel = windowLevel
        self.rulesWidth = rulesWidth
        self.rulesHeight = rulesHeight
        self.rulesOriginX = rulesOriginX
        self.rulesOriginY = rulesOriginY
        self.notesWidth = notesWidth
        self.notesHeight = notesHeight
        self.notesOriginX = notesOriginX
        self.notesOriginY = notesOriginY
        self.rulesOpacity = rulesOpacity
        self.notesOpacity = notesOpacity
        self.isRulesCollapsed = isRulesCollapsed
        self.isNotesCollapsed = isNotesCollapsed
        self.isGhostClickThrough = isGhostClickThrough
        self.fontScale = fontScale
        self.updateChannel = updateChannel
        self.allowEarlyFutureSATReviews = allowEarlyFutureSATReviews
        self.migratedV3Oct16 = migratedV3Oct16
        self.migratedV3_1BlueSpectrum = migratedV3_1BlueSpectrum
    }

    enum CodingKeys: String, CodingKey {
        case pinnedCorner
        case corner
        case isRulesPinned
        case isPinned
        case lastPromptDate
        case windowLevel
        case rulesWidth
        case rulesHeight
        case rulesOriginX
        case rulesOriginY
        case notesWidth
        case notesHeight
        case notesOriginX
        case notesOriginY
        case rulesOpacity
        case notesOpacity
        case isRulesCollapsed
        case isNotesCollapsed
        case isGhostClickThrough
        case fontScale
        case updateChannel
        case allowEarlyFutureSATReviews
        case migratedV3Oct16
        case migratedV3_1BlueSpectrum
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let c = try? container.decode(CornerPosition.self, forKey: .pinnedCorner) {
            self.pinnedCorner = c
        } else if let cLegacy = try? container.decode(CornerPosition.self, forKey: .corner) {
            self.pinnedCorner = cLegacy
        } else {
            self.pinnedCorner = .bottomRight
        }

        self.isRulesPinned = (try? container.decode(Bool.self, forKey: .isRulesPinned)) ?? false
        self.lastPromptDate = (try? container.decode(String.self, forKey: .lastPromptDate)) ?? ""
        self.windowLevel = (try? container.decode(WindowLayerLevel.self, forKey: .windowLevel)) ?? .statusBar
        self.rulesWidth = max(230, min(560, (try? container.decode(Double.self, forKey: .rulesWidth)) ?? 300))
        self.rulesHeight = max(140, min(720, (try? container.decode(Double.self, forKey: .rulesHeight)) ?? 220))
        self.rulesOriginX = try? container.decodeIfPresent(Double.self, forKey: .rulesOriginX)
        self.rulesOriginY = try? container.decodeIfPresent(Double.self, forKey: .rulesOriginY)
        self.notesWidth = max(340, min(820, (try? container.decode(Double.self, forKey: .notesWidth)) ?? 440))
        self.notesHeight = max(260, min(900, (try? container.decode(Double.self, forKey: .notesHeight)) ?? 530))
        self.notesOriginX = try? container.decodeIfPresent(Double.self, forKey: .notesOriginX)
        self.notesOriginY = try? container.decodeIfPresent(Double.self, forKey: .notesOriginY)
        self.rulesOpacity = max(0.25, min(1.0, (try? container.decode(Double.self, forKey: .rulesOpacity)) ?? 0.96))
        self.notesOpacity = max(0.25, min(1.0, (try? container.decode(Double.self, forKey: .notesOpacity)) ?? 0.96))
        self.isRulesCollapsed = (try? container.decode(Bool.self, forKey: .isRulesCollapsed)) ?? false
        self.isNotesCollapsed = (try? container.decode(Bool.self, forKey: .isNotesCollapsed)) ?? false
        self.isGhostClickThrough = (try? container.decode(Bool.self, forKey: .isGhostClickThrough)) ?? false
        self.fontScale = max(0.85, min(1.35, (try? container.decode(Double.self, forKey: .fontScale)) ?? 1.0))
        self.updateChannel = (try? container.decode(String.self, forKey: .updateChannel)) ?? "release"
        self.allowEarlyFutureSATReviews = (try? container.decode(Bool.self, forKey: .allowEarlyFutureSATReviews)) ?? false
        self.migratedV3Oct16 = (try? container.decode(Bool.self, forKey: .migratedV3Oct16)) ?? false
        self.migratedV3_1BlueSpectrum = (try? container.decode(Bool.self, forKey: .migratedV3_1BlueSpectrum)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pinnedCorner, forKey: .pinnedCorner)
        try container.encode(isRulesPinned, forKey: .isRulesPinned)
        try container.encode(lastPromptDate, forKey: .lastPromptDate)
        try container.encode(windowLevel, forKey: .windowLevel)
        try container.encode(rulesWidth, forKey: .rulesWidth)
        try container.encode(rulesHeight, forKey: .rulesHeight)
        try container.encodeIfPresent(rulesOriginX, forKey: .rulesOriginX)
        try container.encodeIfPresent(rulesOriginY, forKey: .rulesOriginY)
        try container.encode(notesWidth, forKey: .notesWidth)
        try container.encode(notesHeight, forKey: .notesHeight)
        try container.encodeIfPresent(notesOriginX, forKey: .notesOriginX)
        try container.encodeIfPresent(notesOriginY, forKey: .notesOriginY)
        try container.encode(rulesOpacity, forKey: .rulesOpacity)
        try container.encode(notesOpacity, forKey: .notesOpacity)
        try container.encode(isRulesCollapsed, forKey: .isRulesCollapsed)
        try container.encode(isNotesCollapsed, forKey: .isNotesCollapsed)
        try container.encode(isGhostClickThrough, forKey: .isGhostClickThrough)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(updateChannel, forKey: .updateChannel)
        try container.encode(allowEarlyFutureSATReviews, forKey: .allowEarlyFutureSATReviews)
        try container.encode(migratedV3Oct16, forKey: .migratedV3Oct16)
        try container.encode(migratedV3_1BlueSpectrum, forKey: .migratedV3_1BlueSpectrum)
    }
}
