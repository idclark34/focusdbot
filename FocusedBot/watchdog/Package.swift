// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Focusd",
    platforms: [
        .macOS(.v13), .iOS(.v15)
    ],
    dependencies: [
        // SQLite wrapper used for local persistence of events
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.3.0")
    ],
    targets: [
        .executableTarget(
            name: "FocusdPhone",
            dependencies: [
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("MultipeerConnectivity")
            ]
        ),
        .executableTarget(
            name: "Focusd",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            linkerSettings: [
                // Need access to AppKit for front-most application queries and
                // ApplicationServices for Accessibility APIs.
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "FocusdUI",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "FocusdBot",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            sources: ["PhoneWatcher.swift", "BotPanelApp.swift", "Safari.swift", "PlantView.swift", "DashboardWindow.swift", "ReflectionWindow.swift", "Database.swift", "ActivityMonitor.swift", "MediaWatcher.swift", "AISummary.swift"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("MultipeerConnectivity")
            ]
        )
    ]
) 