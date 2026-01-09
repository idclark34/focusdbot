import SwiftUI
import AppKit

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

final class DashboardWindowController {
    private let panel: NSPanel
    private let model: BotModel

    init(model: BotModel) {
        self.model = model
        let size = NSSize(width: 320, height: 280)
        self.panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.title = "Focusd Dashboard"
        panel.center()
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let hosting = NSHostingView(rootView: StatsView().environmentObject(model))
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var model: BotModel

    var body: some View {
        TabView {
            todayTab
                .tabItem { 
                    Label("Today", systemImage: "calendar.circle")
                }
            HistoryTab()
                .environmentObject(model)
                .tabItem { 
                    Label("History", systemImage: "chart.bar.fill")
                }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Today tab
    private var todayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's Focus")
                            .font(.title2.bold())
                        Text(Date(), style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "brain.head.profile")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 8)

                // Stats Grid
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 12) {
                    modernStat(icon: "target", label: "Sessions", value: "\(model.completedToday)", tint: .green, bgColor: Color.green.opacity(0.1))
                    modernStat(icon: "timer", label: "Focused", value: "\(model.focusedSecondsToday/60)m", tint: .blue, bgColor: Color.blue.opacity(0.1))
                }
                
                if model.distractedSecondsToday > 0 {
                    modernStat(icon: "exclamationmark.triangle", label: "Distracted", value: "\(model.distractedSecondsToday/60)m", tint: .orange, bgColor: Color.orange.opacity(0.1), fullWidth: true)
                }

                // Recent Reflections (manual + AI summaries)
                RecentReflectionsView()
                    .environmentObject(model)

                Button(action: { model.showDashboard() }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Close")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func modernStat(icon: String, label: String, value: String, tint: Color, bgColor: Color, fullWidth: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !fullWidth {
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.2), lineWidth: 1)
                )
        )
        .if(fullWidth) { view in
            view.gridCellColumns(2)
        }
    }
}

// MARK: History Tab

struct HistoryTab: View {
    @EnvironmentObject var model: BotModel
    @State private var rows: [(day: String, workMin: Int, distractedMin: Int)] = []
    @State private var apps: [(bundle:String,totalMin:Int,avgPerSession:Int)] = []
    @State private var selectedDays: Int = 7
    private let options = [7, 30, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with period selector
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar")
                            .foregroundColor(.blue)
                        Text("Analytics")
                            .font(.title2.bold())
                        Spacer()
                    }
                    
                    Picker("Period", selection: $selectedDays) {
                        ForEach(options, id: \.self) { d in
                            Text("\(d) Days").tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedDays) { _ in reload() }
                }

                // Chart section
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.green)
                            Text("Daily Progress")
                                .font(.headline)
                        }
                        
                        // Chart legend
                        HStack(spacing: 20) {
                            legendItem(color: .green, label: "Focused")
                            legendItem(color: .orange, label: "Distracted")
                        }
                        .padding(.bottom, 8)
                        
                        // Daily bars
                        VStack(spacing: 8) {
                            ForEach(rows, id: \.day) { r in
                                modernDayRow(r)
                            }
                        }
                        
                        // Totals summary
                        VStack(spacing: 8) {
                            Divider()
                            modernSummaryRow()
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.gray.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
                }

                // Top Apps section
                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "app.badge")
                                .foregroundColor(.purple)
                            Text("Top Applications")
                                .font(.headline)
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(apps.prefix(5), id: \.bundle) { app in
                                modernAppRow(app)
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(20)
        }
        .onAppear { reload() }
        .task { reload() } 
    }

    private func reload() {
        print("DEBUG: reload() called, selectedDays=", selectedDays)
        rows = DB.focusStatsLast(days: selectedDays)
        apps = DB.topApps(periodDays: selectedDays)
        print("DEBUG rows →", rows)
        print("DEBUG apps →", apps)
    }

    // MARK: - Modern Design Components
    
    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func modernDayRow(_ row: (day: String, workMin: Int, distractedMin: Int)) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(formatDate(row.day))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Text("\(row.workMin + row.distractedMin)m total")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 60)
                
                modernBar(value: row.workMin, maxValue: maxDailyValue, color: .green)
                modernBar(value: row.distractedMin, maxValue: maxDailyValue, color: .orange)
            }
        }
    }
    
    @ViewBuilder
    private func modernSummaryRow() -> some View {
        let totalWork = rows.reduce(0) { $0 + $1.workMin }
        let totalDistracted = rows.reduce(0) { $0 + $1.distractedMin }
        
        VStack(spacing: 8) {
            HStack {
                Text("Total")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(totalWork + totalDistracted)m")
                    .font(.subheadline.bold())
            }
            
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 60)
                
                modernBar(value: totalWork, maxValue: max(totalWork, totalDistracted, 1), color: .green)
                modernBar(value: totalDistracted, maxValue: max(totalWork, totalDistracted, 1), color: .orange)
            }
        }
    }
    
    @ViewBuilder
    private func modernAppRow(_ app: (bundle: String, totalMin: Int, avgPerSession: Int)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bundleName(app.bundle))
                    .font(.callout)
                    .lineLimit(1)
                
                Text("\(app.totalMin)m total • \(app.avgPerSession)m avg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func modernBar(value: Int, maxValue: Int, color: Color) -> some View {
        GeometryReader { geometry in
            let width = maxValue > 0 ? (CGFloat(value) / CGFloat(maxValue)) * geometry.size.width : 0
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: max(width, value > 0 ? 4 : 0), height: 12)
                
                if value > 0 {
                    Text("\(value)m")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.leading, 4)
                }
            }
        }
        .frame(height: 12)
    }
    
    private var maxDailyValue: Int {
        rows.map { $0.workMin + $0.distractedMin }.max() ?? 1
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "MMM d"
            return outputFormatter.string(from: date)
        }
        
        return dateString
    }

    private func bundleName(_ id: String) -> String {
        if id == Bundle.main.bundleIdentifier { return "FocusdBot" }
        return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id })?.localizedName ?? id
    }
}

// MARK: - Recent Reflections View
struct RecentReflectionsView: View {
    @EnvironmentObject var model: BotModel
    @State private var recentSessions: [SessionSummary] = []
    
    struct SessionSummary: Identifiable {
        let id: Int64
        let summary: String
        let isAI: Bool
        let date: Date
    }
    
    var body: some View {
        if !recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Recent Reflections")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentSessions.prefix(3)) { session in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(session.isAI ? Color.blue : Color.green)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.summary)
                                        .font(.callout)
                                        .lineLimit(2)
                                    Spacer()
                                    if session.isAI {
                                        Image(systemName: "sparkles")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Text(session.date, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.05))
                )
            }
            .onAppear {
                loadRecentSessions()
            }
        }
    }
    
    private func loadRecentSessions() {
        Task {
            do {
                let sessions = try await fetchRecentSessions()
                await MainActor.run {
                    self.recentSessions = sessions
                }
            } catch {
                print("[RecentReflectionsView] Error loading sessions: \(error)")
            }
        }
    }
    
    private func fetchRecentSessions() async throws -> [SessionSummary] {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try DB.shared.read { db in
                    var summaries: [SessionSummary] = []
                    
                    // First add manual summaries (from sessionSummaries array)
                    for (index, summary) in model.sessionSummaries.enumerated() {
                        summaries.append(SessionSummary(
                            id: Int64(-index - 1), // Negative IDs for manual summaries
                            summary: summary,
                            isAI: false,
                            date: Date() // We don't track dates for manual summaries
                        ))
                    }
                    
                    // Then add AI summaries from database where no manual summary exists
                    let aiSessions = try db.execute(sql: """
                        SELECT id, aiSummary, start 
                        FROM session 
                        WHERE completed = 1 
                          AND aiSummary IS NOT NULL 
                          AND aiSummary != ''
                        ORDER BY start DESC 
                        LIMIT 5
                    """) { statement in
                        var results: [SessionSummary] = []
                        while try statement.next() {
                            let id = statement.columnValue(at: 0).int64Value
                            let aiSummary = statement.columnValue(at: 1).stringValue
                            let start = statement.columnValue(at: 2).dateValue
                            
                            results.append(SessionSummary(
                                id: id,
                                summary: aiSummary,
                                isAI: true,
                                date: start
                            ))
                        }
                        return results
                    }
                    
                    // Add AI summaries that don't duplicate manual ones
                    summaries.append(contentsOf: aiSessions)
                    
                    // Sort by date (newer first) and limit to 5
                    summaries.sort { $0.date > $1.date }
                    
                    continuation.resume(returning: Array(summaries.prefix(5)))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
} 