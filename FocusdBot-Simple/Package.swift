// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FocusdBot-Simple",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // SQLite wrapper used for local persistence of events
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.3.0")
    ],
    targets: [
        .executableTarget(
            name: "FocusdBot",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            sources: ["BotPanelApp.swift", "Database.swift", "ReflectionWindow.swift", "Safari.swift", "Chrome.swift"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
