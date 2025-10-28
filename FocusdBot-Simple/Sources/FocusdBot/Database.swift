import Foundation
import GRDB

// MARK: - Session Model (Simplified)
struct Session: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var start: Date
    var end: Date?
    var type: String // "work", "break", etc.
    var plannedMinutes: Int
    var completed: Bool
    
    static let databaseTableName = "session"
}

// MARK: - SessionApp Model (for app usage tracking)
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
            let supportURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FocusdBot-Simple", isDirectory: true)
            try fm.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let dbURL = supportURL.appendingPathComponent("focusedbot-simple.sqlite")
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    /// Database migrations
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Migration 1: Create sessions table (simplified)
        migrator.registerMigration("createSessions") { db in
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
                t.column("type", .text).notNull()
                t.column("plannedMinutes", .integer).notNull()
                t.column("completed", .boolean).notNull().defaults(to: false)
            }
        }
        
        // Migration 2: Create session apps table
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
