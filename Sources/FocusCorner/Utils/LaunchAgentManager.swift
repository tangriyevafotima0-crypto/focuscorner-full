import Foundation

@MainActor
public final class LaunchAgentManager: ObservableObject {
    public static let shared = LaunchAgentManager()

    public let label = "com.focuscorner.overlay"
    @Published public private(set) var isAutostartEnabled: Bool = false

    public var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public var installedAppBinaryPath: String {
        let sysAppBin = "/Applications/FocusCorner.app/Contents/MacOS/FocusCorner"
        if FileManager.default.fileExists(atPath: sysAppBin) {
            return sysAppBin
        }
        let userAppBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/FocusCorner.app/Contents/MacOS/FocusCorner").path
        if FileManager.default.fileExists(atPath: userAppBin) {
            return userAppBin
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".focus_corner/bin/FocusCorner").path
    }

    private init() {
        refreshStatus()
    }

    public func refreshStatus() {
        isAutostartEnabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    public func setAutostart(enabled: Bool) {
        if enabled {
            installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
        refreshStatus()
    }

    public func installLaunchAgent() {
        let executablePath = installedAppBinaryPath

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
                <string>--autostart</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    public func removeLaunchAgent() {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
