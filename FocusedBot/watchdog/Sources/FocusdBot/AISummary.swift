import Foundation

// MARK: - AI Summary Service
final class AISummary {
    
    // MARK: - OpenAI API Configuration
    private static let apiURL = "https://api.openai.com/v1/chat/completions"
    private static let model = "gpt-3.5-turbo"
    private static let maxTokens = 150
    
    // MARK: - Public Interface
    
    static func generate(for sessionId: Int64) async throws -> String? {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_KEY"],
              !apiKey.isEmpty else {
            print("[AISummary] No OPENAI_KEY environment variable found")
            return nil
        }
        
        // Fetch session data
        let sessionData = try await fetchSessionData(sessionId: sessionId)
        guard !sessionData.events.isEmpty else {
            print("[AISummary] No events found for session \(sessionId)")
            return nil
        }
        
        // Build prompt
        let prompt = buildPrompt(from: sessionData)
        
        // Call OpenAI API
        let summary = try await callOpenAI(prompt: prompt, apiKey: apiKey)
        
        // Update session with AI summary
        try await saveAISummary(summary, for: sessionId)
        
        return summary
    }
    
    // MARK: - Private Implementation
    
    private struct SessionData {
        let session: Session
        let events: [SessionEvent]
        let apps: [SessionApp]
    }
    
    private static func fetchSessionData(sessionId: Int64) async throws -> SessionData {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try DB.shared.read { db in
                    // Fetch session
                    guard let session = try Session.fetchOne(db, key: sessionId) else {
                        throw NSError(domain: "AISummary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
                    }
                    
                    // Fetch events
                    let events = try SessionEvent
                        .filter(Column("sessionId") == sessionId)
                        .order(Column("tStart"))
                        .fetchAll(db)
                    
                    // Fetch app usage
                    let apps = try SessionApp
                        .filter(Column("sessionId") == sessionId)
                        .order(Column("seconds").desc)
                        .fetchAll(db)
                    
                    let data = SessionData(session: session, events: events, apps: apps)
                    continuation.resume(returning: data)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private static func buildPrompt(from data: SessionData) -> String {
        var prompt = """
            Summarize this focus session in 1-2 sentences. Be concise and focus on what the user accomplished.
            
            Session: \(data.session.plannedMinutes) minute focus session
            """
        
        // Add app usage summary
        if !data.apps.isEmpty {
            prompt += "\n\nApp Usage:"
            let topApps = Array(data.apps.prefix(5))
            for app in topApps {
                let appName = friendlyAppName(from: app.bundleId)
                let minutes = app.seconds / 60
                if minutes > 0 {
                    prompt += "\n- \(appName): \(minutes) min"
                }
            }
        }
        
        // Add activity events (app switches)
        let appEvents = data.events.filter { $0.kind == "app" }
        if !appEvents.isEmpty {
            prompt += "\n\nActivity Timeline:"
            for event in appEvents.prefix(10) { // Limit to prevent prompt bloat
                let time = formatTime(event.tStart)
                let appName = friendlyAppName(from: event.title)
                let windowTitle = event.detail ?? ""
                if !windowTitle.isEmpty && windowTitle != "(no title)" {
                    prompt += "\n\(time): Switched to \(appName) - \(windowTitle)"
                } else {
                    prompt += "\n\(time): Switched to \(appName)"
                }
            }
        }
        
        // Add media events
        let mediaEvents = data.events.filter { $0.kind == "media" }
        if !mediaEvents.isEmpty {
            prompt += "\n\nMusic:"
            for event in mediaEvents.prefix(5) {
                prompt += "\n- \(event.title)"
                if let detail = event.detail {
                    prompt += " by \(detail)"
                }
            }
        }
        
        prompt += "\n\nProvide a brief, positive summary of what was accomplished during this focus session."
        
        // Ensure prompt isn't too long (roughly 3k tokens = ~2400 characters)
        if prompt.count > 2400 {
            let truncated = String(prompt.prefix(2400))
            prompt = truncated + "...\n\nProvide a brief summary of this focus session."
        }
        
        return prompt
    }
    
    private static func friendlyAppName(from bundleId: String) -> String {
        // Common app bundle ID to friendly name mappings
        let knownApps: [String: String] = [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Chrome",
            "com.microsoft.VSCode": "VS Code",
            "com.apple.dt.Xcode": "Xcode",
            "com.apple.TextEdit": "TextEdit",
            "com.apple.Terminal": "Terminal",
            "com.apple.Music": "Music",
            "com.spotify.client": "Spotify",
            "com.apple.mail": "Mail",
            "com.apple.iCal": "Calendar",
            "com.notion.id": "Notion",
            "com.figma.Desktop": "Figma",
            "com.adobe.photoshop": "Photoshop",
            "com.tinyspeck.slackmacgap": "Slack",
            "us.zoom.xos": "Zoom",
            "com.microsoft.teams": "Teams"
        ]
        
        return knownApps[bundleId] ?? bundleId.components(separatedBy: ".").last ?? bundleId
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private static func callOpenAI(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: apiURL) else {
            throw NSError(domain: "AISummary", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": 0.7
        ] as [String: Any]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "AISummary", code: httpResponse.statusCode, 
                            userInfo: [NSLocalizedDescriptionKey: "OpenAI API error: \(errorMsg)"])
            }
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AISummary", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid API response"])
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func saveAISummary(_ summary: String, for sessionId: Int64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try DB.shared.write { db in
                    try db.execute(sql: """
                        UPDATE session 
                        SET aiSummary = ? 
                        WHERE id = ?
                    """, arguments: [summary, sessionId])
                }
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}