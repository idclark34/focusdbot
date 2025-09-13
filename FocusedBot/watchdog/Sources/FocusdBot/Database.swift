import Foundation
import GRDB


// MARK: - Models
struct Session: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var start: Date
    var end: Date?
    var type: String
    var plannedMinutes: Int
    var completed: Bool
    var aiSummary: String?
    var aiStatus: String?
    var aiError: String?
    var aiJobId: String?
    
    static let databaseTableName = "session"
}

struct SessionEvent: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sessionId: Int64
    var tStart: Date
    var tEnd: Date?
    var kind: String
    var title: String
    var detail: String?
    
    static let databaseTableName = "sessionEvent"
}

struct SessionApp: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var sessionId: Int64
    var bundleId: String
    var seconds: Int
    
    static let databaseTableName = "sessionApp"
}

// MARK: - Database Service
final class DatabaseService {
    // Shared singleton
    static let shared = DatabaseService()
    let dbQueue: DatabaseQueue
    
    private init() {
        do {
            let fm = FileManager.default
            let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Focusd", isDirectory: true)
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            let dbURL = support.appendingPathComponent("focusd.sqlite")
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("DB init failed: \(error)")
        }
    }
    
    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("createSession") { db in
            try db.create(table: "session") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull()
                t.column("end", .datetime)
                t.column("type", .text).notNull()
                t.column("plannedMinutes", .integer).notNull()
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("aiSummary", .text)
                t.column("aiStatus", .text)
                t.column("aiError", .text)
                t.column("aiJobId", .text)
            }
        }
        // For users with an older DB, add missing AI status columns (conditionally)
        m.registerMigration("addAIStatusColumns") { db in
            // Determine existing column names in the 'session' table
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info('session')")
            let existing: Set<String> = Set(rows.compactMap { $0["name"] as String? })

            if !existing.contains("aiStatus") {
                try db.execute(sql: "ALTER TABLE session ADD COLUMN aiStatus TEXT")
            }
            if !existing.contains("aiError") {
                try db.execute(sql: "ALTER TABLE session ADD COLUMN aiError TEXT")
            }
            if !existing.contains("aiJobId") {
                try db.execute(sql: "ALTER TABLE session ADD COLUMN aiJobId TEXT")
            }
        }
        m.registerMigration("createSessionEvent") { db in
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
        m.registerMigration("createSessionApp") { db in
            try db.create(table: "sessionApp") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionId", .integer).notNull().references("session", onDelete: .cascade)
                t.column("bundleId", .text).notNull()
                t.column("seconds", .integer).notNull()
            }
        }
        return m
    }
    
    // MARK: Convenience read/write
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }
    
    // MARK: Stats
    static func focusStatsLast(days: Int) -> [(day: String, workMin: Int, distractedMin: Int)] {
        guard days > 0 else { return [] }
        let today = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -days+1, to: today) else { return [] }
        let fromTime = from.ISO8601Format()

        var rows: [(String, Int, Int)] = []
        do {
            try DB.shared.dbQueue.read { db in
                let sql = """
                    SELECT substr(start,1,10) AS day,
                           SUM(plannedMinutes) as workMin,
                           0 as distractedMin
                    FROM session
                    WHERE start >= ? AND completed = 1
                    GROUP BY day
                    ORDER BY day DESC
                """
                struct DayRow: FetchableRecord, Decodable { let day: String; let workMin: Int; let distractedMin: Int }
                let result: [DayRow] = try DayRow.fetchAll(db, sql: sql, arguments: [fromTime])
                rows = result.map { ($0.day, $0.workMin, $0.distractedMin) }
            }
        } catch {
            print("[DB] focusStatsLast error: \(error)")
        }
        return rows
    }

    static func topApps(periodDays: Int) -> [(bundle: String, totalMin: Int, avgPerSession: Int)] {
        guard periodDays > 0 else { return [] }
        let today = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -periodDays+1, to: today) else { return [] }
        let fromTime = from.ISO8601Format()

        var res: [(String, Int, Int)] = []
        do {
            try DB.shared.dbQueue.read { db in
                let sql = """
                    SELECT bundleId,
                           SUM(seconds)/60 as totalMin,
                           AVG(seconds)/60 as avgMin
                    FROM sessionApp
                    WHERE sessionId IN (
                        SELECT id FROM session WHERE start >= ? AND completed = 1
                    )
                    GROUP BY bundleId
                    ORDER BY totalMin DESC
                    LIMIT 10
                """
                struct AppAgg: FetchableRecord, Decodable { let bundleId: String; let totalMin: Int; let avgMin: Int }
                let rows: [AppAgg] = try AppAgg.fetchAll(db, sql: sql, arguments: [fromTime])
                res = rows.map { ($0.bundleId, $0.totalMin, $0.avgMin) }
            }
        } catch {
            print("[DB] topApps error: \(error)")
        }
        return res
    }
}

// MARK: - Convenience alias
typealias DB = DatabaseService

// MARK: - Stats helpers used by DashboardWindow
#if false
extension DatabaseService {
    func focusStatsLast(days: Int) -> [(day: String, workMin: Int, distractedMin: Int)] {
        let today = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -days+1, to: today) else { return [] }
        let fromTime = from.ISO8601Format()
        var rows: [(String, Int, Int)] = []
        try? dbQueue.read { db in
            let sql = """
                SELECT substr(start,1,10) AS day,
                       SUM(plannedMinutes) as workMin,
                       0 as distractedMin
                FROM session
                WHERE start >= ? AND completed = 1
                GROUP BY day
                ORDER BY day DESC
            """
            let stmt = try db.makeStatement(sql: sql)
            try stmt.execute(arguments: [fromTime])
            while stmt.next() {
                let day = stmt.columnString(at: 0) ?? ""
                let work = Int(stmt.columnInt(at: 1))
                let dis = Int(stmt.columnInt(at: 2))
                rows.append((day, work, dis))
            }
        }
        return rows
    }
    
    func topApps(periodDays: Int) -> [(bundle:String,totalMin:Int,avgPerSession:Int)] {
        let today = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -periodDays+1, to: today) else { return [] }
        let fromTime = from.ISO8601Format()
        var res: [(String,Int,Int)] = []
        try? dbQueue.read { db in
            let sql = """
                SELECT bundleId, SUM(seconds)/60 as totalMin, AVG(seconds)/60 as avgMin
                FROM sessionApp
                WHERE sessionId IN (SELECT id FROM session WHERE start >= ? AND completed = 1)
                GROUP BY bundleId
                ORDER BY totalMin DESC
                LIMIT 10
            """
            let stmt = try db.makeStatement(sql: sql)
            try stmt.execute(arguments: [fromTime])
            while stmt.next() {
                let bundle = stmt.columnString(at: 0) ?? ""
                let total = Int(stmt.columnInt(at: 1))
                let avg = Int(stmt.columnInt(at: 2))
                res.append((bundle,total,avg))
            }
        }
        return res
    }
}
#endif
