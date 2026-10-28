import AppKit
import Foundation
import Darwin

// KERNEL-LEVEL SINGLE INSTANCE LOCK (flock)
let lockPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".focus_corner/focuscorner.lock").path
try? FileManager.default.createDirectory(
    atPath: (lockPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true,
    attributes: nil
)
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 {
    if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        // Another instance of FocusCorner already holds the kernel lock -> exit immediately!
        exit(0)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
