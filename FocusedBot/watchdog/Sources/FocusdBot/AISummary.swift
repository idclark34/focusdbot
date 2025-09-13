import Foundation
import GRDB

enum AISummary {
    struct Payload: Codable {
        let sessionId: Int64
        let startedAt: String
        let endedAt: String
        let durationMin: Int
        let events: [Event]
        let apps: [AppUsage]
    }
    struct Event: Codable { let t: String; let kind: String; let title: String; let detail: String? }
    struct AppUsage: Codable { let bundleId: String; let seconds: Int }

    static func generate(for sessionId: Int64) async throws -> String? {
        // If no proxy configured, do nothing
        guard let proxy = ProcessInfo.processInfo.environment["FOCUSD_PROXY_URL"], let base = URL(string: proxy)?.appendingPathComponent("v1/summary") else {
            print("[AI] FOCUSD_PROXY_URL not set; skipping summary")
            return nil
        }
        // Build compact payload from local DB
        let info: (Date, Date, Int)? = try DB.shared.read { db in
            struct SessionInfoRow: FetchableRecord, Decodable { let start: Date; let end: Date; let plannedMinutes: Int }
            return try SessionInfoRow
                .fetchOne(db, sql: "SELECT start, COALESCE(end, start) AS end, plannedMinutes FROM session WHERE id = ?", arguments: [sessionId])
                .map { ($0.start, $0.end, $0.plannedMinutes) }
        }
        guard let (start, end, planned) = info else { return nil }

        let events: [Event] = try DB.shared.read { db in
            try EventRow
                .fetchAll(db, sql: "SELECT tStart, kind, title, detail FROM sessionEvent WHERE sessionId = ? ORDER BY tStart", arguments: [sessionId])
                .map { row in Event(t: row.tStart.ISO8601Format(), kind: row.kind, title: row.title, detail: row.detail) }
        }
        let apps: [AppUsage] = try DB.shared.read { db in
            try AppRow
                .fetchAll(db, sql: "SELECT bundleId, seconds FROM sessionApp WHERE sessionId = ? ORDER BY seconds DESC", arguments: [sessionId])
                .map { AppUsage(bundleId: $0.bundleId, seconds: $0.seconds) }
        }

        let payload = Payload(sessionId: sessionId,
                              startedAt: start.ISO8601Format(),
                              endedAt: end.ISO8601Format(),
                              durationMin: planned,
                              events: events,
                              apps: apps)

        var req = URLRequest(url: base)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret = ProcessInfo.processInfo.environment["FOCUSD_CLIENT_SECRET"] { req.setValue(secret, forHTTPHeaderField: "x-client-secret") }
        req.httpBody = try JSONEncoder().encode(payload)

        print("[AI] POST → \(base.absoluteString)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 202 {
            // Poll job status until done
            struct JobResp: Decodable { let jobId: String?; let id: String?; let status: String?; let summary: String? }
            let job = try JSONDecoder().decode(JobResp.self, from: data)
            let jobId = job.jobId ?? job.id
            guard let jid = jobId else { return nil }
            print("[AI] queued jobId=\(jid)")
            // Build status URL: if base ends with /v1/summary, append /{jobId}
            let statusURL = base.appendingPathComponent(jid)
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                var sreq = URLRequest(url: statusURL)
                if let secret = ProcessInfo.processInfo.environment["FOCUSD_CLIENT_SECRET"] { sreq.setValue(secret, forHTTPHeaderField: "x-client-secret") }
                let (sdata, _) = try await URLSession.shared.data(for: sreq)
                let st = try? JSONDecoder().decode(JobResp.self, from: sdata)
                if let st = st { print("[AI] status=\(st.status ?? "?") hasSummary=\(st.summary != nil)") }
                if let st = st, st.status == "done", let text = st.summary, !text.isEmpty { return text }
                if let st = st, st.status == "error" { return nil }
            }
            return nil
        }
        if (200..<300).contains(http.statusCode) {
            // Direct summary text
            print("[AI] received 2xx body")
            return String(data: data, encoding: .utf8)
        }
        print("[AI] unexpected status=\(http.statusCode)")
        return nil
    }
}

// Helper rows for lightweight fetch
private struct EventRow: FetchableRecord, Decodable { let tStart: Date; let kind: String; let title: String; let detail: String? }
private struct AppRow: FetchableRecord, Decodable { let bundleId: String; let seconds: Int }