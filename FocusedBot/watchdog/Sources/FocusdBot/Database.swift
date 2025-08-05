import Foundation
import GRDB

// MARK: - Session Model
struct Session: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var start: Date
    var end: Date?
    var type: String // "work", "break", etc.
    var plannedMinutes: Int
    var completed: Bool
    var aiSummary: String?
    
    static let databaseTableName = "session"
}

// MARK: - SessionEvent Model  
struct SessionEvent: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sessionId: Int64
    var tStart: Date
    var tEnd: Date?
    var kind: String // "app", "media", etc.
    var title: String
    var detail: String?
    
    static let databaseTableName = "sessionEvent"
    
    static let session = belongsTo(Session.self)
}

// MARK: - SessionApp Model (for backward compatibility)
struct SessionApp: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sessionId: Int64
    var bundleId: String
    var seconds: Int
    
    static let databaseTableName = "sessionApp"
    
    static let session = belongsTo(Session.self)
}

// MARK: - Database Service
final class DatabaseService {
    static let shared = DatabaseService()
    
    let dbQueue: DatabaseQueue
    
    private init() {
        do {
            let fm = FileManager.default
            let supportURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Focusd", isDirectory: true)
            try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let dbURL = supportURL.appendingPathComponent("focusd.sqlite")
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    /// Database migrations
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Migration 1: Create events table (from main.swift)
        migrator.registerMigration("createEvents") { db in
            try db.create(table: "event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("bundleId", .text).notNull()
                t.column("windowTitle", .text).notNull()
            }
        }
        
        // Migration 2: Create input events table (from main.swift)
        migrator.registerMigration("createInputEvents") { db in
            try db.create(table: "input_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull()
            }
        }
        
        // Migration 3: Create sessions table
        migrator.registerMigration("createSessions") { db in
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
                t.column("type", .text).notNull()
                t.column("plannedMinutes", .integer).notNull()
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("aiSummary", .text)
            }
        }
        
        // Migration 4: Create session events table
        migrator.registerMigration("createSessionEvents") { db in
            try db.create(table: "sessionEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull().references("session", onDelete: .cascade)
                t.column("tStart", .datetime).notNull()
                t.column("tEnd", .datetime)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("detail", .text)
            }
        }
        
        // Migration 5: Create session apps table (for backward compatibility)
        migrator.registerMigration("createSessionApps") { db in
            try db.create(table: "sessionApp") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull().references("session", onDelete: .cascade)
                t.column("bundleId", .text).notNull()
                t.column("seconds", .integer).notNull()
            }
        }
        
        return migrator
    }
    
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.write(block)
    }
    
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        return try dbQueue.read(block)
    }
}

// MARK: - Global database instance alias for compatibility
typealias DB = DatabaseService