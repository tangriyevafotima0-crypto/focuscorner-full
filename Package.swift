// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FocusCorner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "FocusCorner",
            targets: ["FocusCorner"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FocusCorner",
            path: "Sources/FocusCorner",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
