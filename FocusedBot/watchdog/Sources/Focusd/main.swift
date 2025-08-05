import Foundation
import AppKit
import GRDB
import ApplicationServices
import IOKit

// MARK: - Helpers for Active Window Title

/// Returns the title of the front-most window using the Accessibility API.
private func activeWindowTitle() -> String? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window)
    guard result == .success, let win = window else { return nil }

    var title: CFTypeRef?
    if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success {
        return title as? String
    }
    return nil
}

// MARK: - Database

struct Event: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var start: Date
    var end: Date
    var bundleId: String
    var windowTitle: String
}

final class DatabaseService {
    let dbQueue: DatabaseQueue

    init() throws {
        let fm = FileManager.default
        let supportURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Focusd", isDirectory: true)
        try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let dbURL = supportURL.appendingPathComponent("focusd.sqlite")
        dbQueue = try DatabaseQueue(path: dbURL.path)
        try migrator.migrate(dbQueue)
    }

    /// Database migrations
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createEvents") { db in
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("bundleId", .text).notNull()
                t.column("windowTitle", .text).notNull()
            }
        }
        return migrator
    }

    func insert(event: Event) throws {
        try dbQueue.write { db in
            try event.insert(db)
        }
    }
}

// MARK: - Input Events

struct InputEvent: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var timestamp: Date
}

extension DatabaseService {
    fileprivate func insert(input event: InputEvent) throws {
        try dbQueue.write { db in
            try event.insert(db)
        }
    }
}

final class InputMonitor {
    private let db: DatabaseService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(database: DatabaseService) {
        self.db = database
    }

    func start() {
        // Listen to both key and mouse events globally.
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let info = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.handle(eventType: type)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            fputs("[Focusd] Failed to create event tap. Ensure the app has Input Monitoring permission in System Settings → Privacy & Security.\n", stderr)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(eventType: CGEventType) {
        let evt = InputEvent(id: nil, timestamp: Date())
        try? db.insert(input: evt)
    }
}

// MARK: - Update Database Migrator
// Extend migrator with new table creation
extension DatabaseService {
    private static let createInputEventsMigrationName = "createInputEvents"

    fileprivate var extendedMigrator: DatabaseMigrator {
        var migrator = self.migrator // base migrator defined earlier
        migrator.registerMigration(Self.createInputEventsMigrationName) { db in
            try db.create(table: "input_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
            }
        }
        return migrator
    }
    // Override initializer to use extendedMigrator
    convenience init(migratingWithInput: Bool) throws {
        try self.init()
        try extendedMigrator.migrate(dbQueue)
    }
}

// MARK: - Focus Logger

final class FocusLogger {
    private let db: DatabaseService

    private var lastBundleId: String?
    private var lastTitle: String?
    private var spanStart: Date?

    private var timer: DispatchSourceTimer?

    init(database: DatabaseService) {
        self.db = database
    }

    func start() {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary) else {
            fputs("[Focusd] Accessibility permission is required. Grant it in System Settings → Privacy & Security → Accessibility.\n", stderr)
            exit(1)
        }

        // Prime state
        updateState()

        let queue = DispatchQueue(label: "focusd.timer")
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 1.0)
        timer?.setEventHandler { [weak self] in
            self?.updateState()
        }
        timer?.resume()
    }

    private func updateState() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = app.bundleIdentifier ?? "unknown"
        let title = activeWindowTitle() ?? "(no title)"

        let now = Date()
        if lastBundleId == nil {
            // first run
            lastBundleId = bundleId
            lastTitle = title
            spanStart = now
            return
        }

        // If nothing changed, continue span
        if bundleId == lastBundleId && title == lastTitle {
            return
        }

        // otherwise flush previous span
        if let start = spanStart, let prevBundle = lastBundleId, let prevTitle = lastTitle {
            let event = Event(id: nil, start: start, end: now, bundleId: prevBundle, windowTitle: prevTitle)
            try? db.insert(event: event)
        }

        // start new span
        lastBundleId = bundleId
        lastTitle = title
        spanStart = now
    }
}

// MARK: - Main

do {
    let database = try DatabaseService(migratingWithInput: true)
    let logger = FocusLogger(database: database)
    let inputMonitor = InputMonitor(database: database)
    inputMonitor.start()
    logger.start()
    print("Focusd logger running… (press Ctrl+C to quit)")
    RunLoop.main.run()
} catch {
    fputs("Focusd failed to start: \(error)\n", stderr)
    exit(1)
} 