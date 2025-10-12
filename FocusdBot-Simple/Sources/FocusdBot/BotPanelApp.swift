import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Clock style options
enum ClockStyle: String, CaseIterable, Identifiable, Codable {
    case numeric
    case gradient
    case neon
    case dotMatrix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .numeric: return "Numeric"
        case .gradient: return "Gradient"
        case .neon: return "Neon"
        case .dotMatrix: return "Dots"
        }
    }
}

// MARK: - Character style options
enum CharacterStyle: String, CaseIterable, Identifiable, Codable {
    case robot
    case plant

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Helper for active window
private func activeWindowInfo() -> (bundle: String, title: String) {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return ("(none)", "No active window")
    }
    let bundleId = app.bundleIdentifier ?? app.localizedName ?? "unknown"
    return (bundleId, "(no title)")
}

// MARK: - ViewModel (simplified)
@MainActor
class BotModel: ObservableObject {
    enum PomodoroState { case idle, running, success, breakTime, distracted }

    @Published var durationMinutes: Int = UserDefaults.standard.integer(forKey: "botDurationMinutes").nonZeroOrDefault(25)

    @Published var pomodoroState: PomodoroState = .idle
    @Published var remaining: Int = 25*60   // used for work timer or break timer
    @Published var progress: Double = 0.0 // 0.0 - 1.0

    // Timer font size (points)
    @Published var fontSize: CGFloat = 24

    // Optional debug duration override (seconds)
    @Published var testDurationSeconds: Int? = nil
    private let breakTotal: Int = 5 * 60
    private var pomodoroTotal: Int { testDurationSeconds ?? (durationMinutes * 60) }
    private var sessionAllowedBundles: Set<String> = []
    @Published var globalAllowed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "botGlobalAllowed") ?? [])

    private let selfBundle: String = Bundle.main.bundleIdentifier ?? ""

    // Per-app seconds spent during current focus session
    private var sessionAppSeconds: [String: Int] = [:]
    private var currentSessionId: Int64?

    @Published var blink: Bool = false // for animation toggle

    // Fast pulse toggle for angry state animation
    @Published var pulse: Bool = false

    // Flip clock counter for continuous rotation
    @Published var flipCount: Int = 0

    // Random wiggle
    @Published var wiggleOffset: CGSize = .zero
    @Published var wiggleRotation: Double = 0

    // Confetti trigger counter
    @Published var confettiBurst: Int = 0

    // Color cycle hue (avoids red)
    @Published var bodyHue: Double = 0.05

    // ==== Daily stats ====
    @Published var completedToday: Int = 0
    @Published var focusedSecondsToday: Int = 0
    @Published var distractedSecondsToday: Int = 0
    private var statsDate: Date = Date()

    // Session reflections (recent)
    @Published var sessionSummaries: [String] = []

    // Website permissions
    struct WebRule: Codable, Identifiable {
        var id = UUID()
        var domain: String
        var enabled: Bool
    }

    @Published var webRules: [WebRule] = []
    private var sessionAllowedWebsites: Set<String> = []

    // Clock style preference
    @Published var clockStyle: ClockStyle = ClockStyle(rawValue: UserDefaults.standard.string(forKey: "botClockStyle") ?? ClockStyle.numeric.rawValue) ?? .numeric {
        didSet { UserDefaults.standard.set(clockStyle.rawValue, forKey: "botClockStyle") }
    }

    // Character style preference
    @Published var characterStyle: CharacterStyle = CharacterStyle(rawValue: UserDefaults.standard.string(forKey: "botCharacterStyle") ?? CharacterStyle.robot.rawValue) ?? .robot {
        didSet { UserDefaults.standard.set(characterStyle.rawValue, forKey: "botCharacterStyle") }
    }

    // Minimize to menu bar preference
    @Published var isMinimized: Bool = UserDefaults.standard.bool(forKey: "botIsMinimized") {
        didSet { 
            UserDefaults.standard.set(isMinimized, forKey: "botIsMinimized")
            // Notify the panel controller to show/hide
            NotificationCenter.default.post(name: .botMinimizeToggled, object: nil)
        }
    }

    // Single high-accuracy timer source for all ticks/animations
    private var tickTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.focusdbot.timer", qos: .userInitiated)
    private var subTick: Int = 0 // used for simple pulse/blink cadence
    private var activationObserver: Any?

    init() {
        // main tick using DispatchSourceTimer to avoid drift
        loadWebRules()
        startAccurateTimer()

        // App activation observer for instant reaction
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self = self else { return }
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundle = app.bundleIdentifier else { return }

                let allowed = bundle == self.selfBundle || self.sessionAllowedBundles.contains(bundle) || self.globalAllowed.contains(bundle)

                switch self.pomodoroState {
                case .running where !allowed:
                    self.pomodoroState = .distracted
                    NotificationCenter.default.post(name: .botShowPanel, object: nil)
                case .distracted where allowed:
                    self.pomodoroState = .running
                    if self.isMinimized {
                        NotificationCenter.default.post(name: .botHidePanel, object: nil)
                    }
                default:
                    break
                }
            }
        }
    }

    deinit {
        Task { @MainActor in
            stopAccurateTimer()
        }
        if let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Accurate timer management
    private func startAccurateTimer() {
        stopAccurateTimer()
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        // 0.25 second cadence to allow higher-frequency pulses while keeping 1s logic in tick()
        t.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(25))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.subTick = (self.subTick + 1) % 16
                // Pulse cadence per state:
                // - distracted: every 0.25s (fast)
                // - running (focus): every 2.0s (slow)
                // - other states: every 1.0s (medium)
                switch self.pomodoroState {
                case .distracted:
                    self.pulse.toggle()
                case .running:
                    if self.subTick % 8 == 0 { self.pulse.toggle() }
                default:
                    if self.subTick % 4 == 0 { self.pulse.toggle() }
                }
                // Run per-second logic
                if self.subTick % 4 == 0 {
                    self.tick()
                }
            }
        }
        t.resume()
        tickTimer = t
    }

    private func stopAccurateTimer() {
        tickTimer?.setEventHandler {}
        tickTimer?.cancel()
        tickTimer = nil
    }

    // MARK: - Intents
    func startPomodoro() {
        let current = activeWindowInfo().bundle
        sessionAllowedBundles = [current]
        remaining = pomodoroTotal
        progress = 0
        pomodoroState = .running

        sessionAppSeconds = [:]

        // insert session row
        currentSessionId = try? DB.shared.write { db in
            var s = Session(id: nil, start: Date(), end: nil, type: "work", plannedMinutes: durationMinutes, completed: false)
            try s.insert(db)
            return db.lastInsertedRowID
        }
    }

    func pauseSession() {
        guard pomodoroState == .running || pomodoroState == .distracted || pomodoroState == .breakTime else { return }
        pomodoroState = .idle
        currentSessionId = nil
        clearPersistedSession()
    }

    func finishSession() {
        finalizeSession()
        pomodoroState = .idle
        currentSessionId = nil
        clearPersistedSession()
    }

    func setDuration(minutes: Int) {
        guard minutes > 0 else { return }
        testDurationSeconds = nil // turn off debug
        durationMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "botDurationMinutes")
        if pomodoroState == .running {
            // restart session with new duration on next start
            pomodoroState = .idle
        }
    }

    func enableTest30s() {
        setTestDuration(30)
    }

    // Generic setter so we can support multiple test durations
    func setTestDuration(_ seconds: Int?) {
        testDurationSeconds = seconds
        if pomodoroState == .running {
            pomodoroState = .idle
        }
    }

    func setClockStyle(_ style: ClockStyle) {
        clockStyle = style
    }

    func setCharacterStyle(_ style: CharacterStyle) {
        characterStyle = style
    }

    func toggleMinimize() {
        isMinimized.toggle()
    }

    // MARK: - App Management
    func toggleAppAllowed(_ bundle: String) {
        if globalAllowed.contains(bundle) {
            globalAllowed.remove(bundle)
        } else {
            globalAllowed.insert(bundle)
        }
        UserDefaults.standard.set(Array(globalAllowed), forKey: "botGlobalAllowed")
    }

    // MARK: - Website Management
    private let webRuleKey = "botWebRules"

    private func loadWebRules() {
        if let data = UserDefaults.standard.data(forKey: webRuleKey),
           let rules = try? JSONDecoder().decode([WebRule].self, from: data) {
            // sanitize any previously-saved domains (strip scheme, path, www.)
            self.webRules = rules.map { r in
                WebRule(domain: sanitizeDomainInput(r.domain) ?? r.domain.lowercased(), enabled: r.enabled)
            }
            saveWebRules()
        } else {
            // migrate old key if exists
            if let old = UserDefaults.standard.stringArray(forKey: "botAllowedWebsites") {
                self.webRules = old.compactMap { d in
                    sanitizeDomainInput(d).map { WebRule(domain: $0, enabled: true) }
                }
                saveWebRules()
                UserDefaults.standard.removeObject(forKey: "botAllowedWebsites")
            }
        }
    }

    private func saveWebRules() {
        if let data = try? JSONEncoder().encode(webRules) {
            UserDefaults.standard.set(data, forKey: webRuleKey)
        }
    }

    func addWebsiteRule(_ domain: String) {
        let cleaned = sanitizeDomainInput(domain) ?? domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return }
        if let idx = webRules.firstIndex(where: { $0.domain == cleaned }) {
            webRules[idx].enabled = true
        } else {
            webRules.append(WebRule(domain: cleaned, enabled: true))
        }
        saveWebRules()
    }

    func toggleRule(id: WebRule.ID) {
        guard let idx = webRules.firstIndex(where: { $0.id == id }) else { return }
        webRules[idx].enabled.toggle()
        saveWebRules()
    }

    func removeRule(id: WebRule.ID) {
        webRules.removeAll { $0.id == id }
        saveWebRules()
    }

    private func tick() {
        // ==== Daily rollover check ====
        if !Calendar.current.isDate(statsDate, inSameDayAs: Date()) {
            // new day – reset counters
            completedToday = 0
            focusedSecondsToday = 0
            distractedSecondsToday = 0
            statsDate = Date()
        }

        // simple blink animation toggle and flip counter
        blink.toggle()
        flipCount += 1

        // advance body hue for color cycling
        bodyHue += 0.01
        if bodyHue > 0.95 { bodyHue = 0.05 } // wrap to skip red zone

        // random wiggle every few seconds
        if Int.random(in: 0...3) == 0 { // 25% chance each second
            let base: ClosedRange<Double> = pomodoroState == .distracted ? -8...8 : -4...4
            let dx = Double.random(in: base)
            let dy = Double.random(in: base)
            wiggleOffset = CGSize(width: dx, height: dy)
            wiggleRotation = pomodoroState == .distracted ? Double.random(in: -10...10) : Double.random(in: -6...6)
        } else {
            // ease back to center
            wiggleOffset = .zero
            wiggleRotation = 0
        }

        let currentBundle = activeWindowInfo().bundle

        // track per-app usage when session active
        if pomodoroState == .running || pomodoroState == .distracted {
            sessionAppSeconds[currentBundle, default: 0] += 1
        }

        let allowed = (currentBundle == selfBundle) || sessionAllowedBundles.contains(currentBundle) || globalAllowed.contains(currentBundle)

        var reallyAllowed = allowed

        // Check website rules for Safari ONLY if Safari is not already allowed as an app.
        if currentBundle == "com.apple.Safari" && !allowed {
            if let url = Safari.frontmostTabURL(), let h = url.host?.lowercased() {
                let host = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
                let isWebsiteAllowed = webRules.contains { rule in
                    guard rule.enabled else { return false }
                    let d = rule.domain
                    return host == d || host.hasSuffix("." + d)
                }
                reallyAllowed = isWebsiteAllowed
            } else {
                reallyAllowed = false // No URL, probably a new tab page
            }
        }

    // Sanitize input like "https://www.youtube.com/watch?v=.." to "youtube.com"
    private func sanitizeDomainInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // Try URL parsing first
        if let url = URL(string: trimmed), let host = url.host {
            return normalizeHost(host)
        }
        // If it doesn't parse as URL, try adding a scheme and reparse
        if let url = URL(string: "https://" + trimmed), let host = url.host {
            return normalizeHost(host)
        }
        // Fallback: strip any path and www.
        let lower = trimmed.lowercased()
        let base = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        return normalizeHost(base)
    }

    private func normalizeHost(_ host: String) -> String {
        let lower = host.lowercased()
        if lower.hasPrefix("www.") { return String(lower.dropFirst(4)) }
        return lower
        }

        switch pomodoroState {
        case .running:
            if !reallyAllowed {
                pomodoroState = .distracted
                NotificationCenter.default.post(name: .botShowPanel, object: nil)
                // keep timer visible in status bar
                Task { @MainActor in StatusBarTimer.shared.update(text: formatTime(remaining)) }
                return
            }
            remaining -= 1
            progress = 1.0 - Double(remaining) / Double(pomodoroTotal)
            focusedSecondsToday += 1 // count productive second
            // update status bar timer
            Task { @MainActor in StatusBarTimer.shared.update(text: formatTime(remaining)) }
            if remaining <= 0 {
                completedToday += 1 // finished pomodoro
                pomodoroState = .success
                confettiBurst += 1

                // Prompt user for reflection
                promptForSessionName()

                // after short delay switch to break phase
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, self.pomodoroState == .success else { return }
                    self.remaining = self.breakTotal
                    self.pomodoroState = .breakTime
                }
            }
        case .distracted:
            // resume if back to allowed app
            if reallyAllowed {
                pomodoroState = .running
                if isMinimized {
                    NotificationCenter.default.post(name: .botHidePanel, object: nil)
                }
            }
            distractedSecondsToday += 1 // count distracted second
            Task { @MainActor in StatusBarTimer.shared.update(text: formatTime(remaining)) }
        case .breakTime:
            // countdown break
            remaining -= 1
            Task { @MainActor in StatusBarTimer.shared.update(text: formatTime(remaining)) }
            if remaining <= 0 {
                pomodoroState = .idle
                currentSessionId = nil
            }
        default:
            break
        }

        persistInFlightIfNeeded()
        // hide timer if no longer active
        let activeNow = pomodoroState == .running || pomodoroState == .distracted || pomodoroState == .breakTime
        if !activeNow {
            Task { @MainActor in StatusBarTimer.shared.update(text: nil) }
        }
    }

    // Sanitize input like "https://www.youtube.com/watch?v=.." to "youtube.com"
    private func sanitizeDomainInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // Try URL parsing first
        if let url = URL(string: trimmed), let host = url.host {
            return normalizeHost(host)
        }
        // If it doesn't parse as URL, try adding a scheme and reparse
        if let url = URL(string: "https://" + trimmed), let host = url.host {
            return normalizeHost(host)
        }
        // Fallback: strip any path and www.
        let lower = trimmed.lowercased()
        let base = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        return normalizeHost(base)
    }

    private func normalizeHost(_ host: String) -> String {
        let lower = host.lowercased()
        if lower.hasPrefix("www.") { return String(lower.dropFirst(4)) }
        return lower
    }

    // MARK: - Persistence of in-flight session (robust restarts)
    private var persistCounter: Int = 0
    private let persistEverySeconds: Int = 5

    private func persistInFlightIfNeeded() {
        persistCounter += 1
        guard persistCounter % persistEverySeconds == 0 else { return }
        let defaults = UserDefaults.standard
        let active = pomodoroState == .running || pomodoroState == .distracted || pomodoroState == .breakTime
        defaults.set(active, forKey: "bot_sessionActive")
        if active {
            defaults.set(remaining, forKey: "bot_sessionRemaining")
            defaults.set(durationMinutes, forKey: "bot_sessionPlannedMinutes")
            defaults.set(currentSessionId, forKey: "bot_sessionId")
        } else {
            clearPersistedSession()
        }
    }

    private func clearPersistedSession() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "bot_sessionActive")
        d.removeObject(forKey: "bot_sessionRemaining")
        d.removeObject(forKey: "bot_sessionPlannedMinutes")
        d.removeObject(forKey: "bot_sessionId")
    }

    // MARK: Reflection prompt
    private func promptForSessionName() {
        // First, complete the session in the database
        finalizeSession()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Build slices for pie chart
            let nameFor: (String) -> String = { bundle in
                if bundle == self.selfBundle { return "FocusdBot" }
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
                   let name = app.localizedName { return name }
                return bundle
            }
            
            let slices = self.sessionAppSeconds.map { (bundle, seconds) in
                AppSlice(name: nameFor(bundle), seconds: seconds, color: Color.random)
            }.sorted { $0.seconds > $1.seconds }
            
            let controller = ReflectionWindowController(model: self, slices: slices, sessionId: self.currentSessionId)
            controller.show()
        }
    }
    
    private func finalizeSession() {
        guard let sessionId = currentSessionId else { return }
        
        try? DB.shared.write { db in
            // Mark session as completed
            try db.execute(sql: """
                UPDATE session 
                SET completed = 1, end = ? 
                WHERE id = ?
            """, arguments: [Date(), sessionId])

            // Insert app usage records
            for (bundle, seconds) in sessionAppSeconds {
                var appRecord = SessionApp(id: nil, sessionId: sessionId, bundleId: bundle, seconds: seconds)
                try appRecord.insert(db)
            }
        }
        
        // Clear app seconds for next session
        sessionAppSeconds = [:]
    }
}

// MARK: - Panel Controller
final class BotPanelController {
    private var panel: NSPanel!
    private let model: BotModel
    private var minimizeObserver: NSObjectProtocol?
    private var showObserver: NSObjectProtocol?
    private var hideObserver: NSObjectProtocol?

    init(model: BotModel) {
        self.model = model
        let sizeDim: CGFloat = 200
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 400, height: 300)
        let origin = CGPoint(x: screen.maxX - sizeDim - 20, y: screen.minY + 20)

        panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: sizeDim, height: sizeDim)),
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: RobotView().environmentObject(model))
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: sizeDim, height: sizeDim))
        panel.contentView = hosting
        
        // Set initial visibility based on minimize state
        Task { @MainActor in
            if model.isMinimized {
                panel.orderOut(nil)
            } else {
                panel.makeKeyAndOrderFront(nil)
                panel.orderFrontRegardless()
            }
        }
        
        // Listen for minimize toggle notifications
        minimizeObserver = NotificationCenter.default.addObserver(
            forName: .botMinimizeToggled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateVisibility()
            }
        }

        // Show panel on distraction even if minimized
        showObserver = NotificationCenter.default.addObserver(forName: .botShowPanel, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.panel.makeKeyAndOrderFront(nil)
                self.panel.orderFrontRegardless()
            }
        }
        // Hide panel again if preference is minimized when distraction ends
        hideObserver = NotificationCenter.default.addObserver(forName: .botHidePanel, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.model.isMinimized {
                    self.panel.orderOut(nil)
                }
            }
        }
        
        print("[Bot] Panel constructed")
    }
    
    deinit {
        if let observer = minimizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = showObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = hideObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    @MainActor
    private func updateVisibility() {
        if model.isMinimized {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }
}

// MARK: - Menu Content View (Simplified)
struct BotMenuView: View {
    @EnvironmentObject var model: BotModel
    @State private var customMinutes: String = ""
    @State private var showCustomInput: Bool = false
    @State private var newWebsite: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("🤖 FocusdBot Simple")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.durationMinutes)min")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(model.completedToday) today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Duration picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duration:")
                    Spacer()
                    Button(showCustomInput ? "Presets" : "Custom") {
                        showCustomInput.toggle()
                        if !showCustomInput {
                            customMinutes = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if showCustomInput {
                    HStack {
                        TextField("Minutes (1-120)", text: $customMinutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        Button("Set") {
                            if let minutes = Int(customMinutes), minutes >= 1 && minutes <= 120 {
                                model.setDuration(minutes: minutes)
                                showCustomInput = false
                                customMinutes = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(customMinutes.isEmpty || Int(customMinutes) == nil || Int(customMinutes)! < 1 || Int(customMinutes)! > 120)
                        
                        Spacer()
                    }
                } else {
                    Picker("", selection: Binding(
                        get: { model.durationMinutes },
                        set: { model.setDuration(minutes: $0) }
                    )) {
                        Text("15m").tag(15)
                        Text("25m").tag(25)
                        Text("45m").tag(45)
                        Text("60m").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Test mode
            HStack {
                Text("Quick Test:")
                Spacer()
                Button("30s") {
                    model.enableTest30s()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Clock style
            HStack {
                Text("Clock Style:")
                Spacer()
                Picker("", selection: Binding(
                    get: { model.clockStyle },
                    set: { model.setClockStyle($0) }
                )) {
                    ForEach(ClockStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            Divider()

            // Main action button
            switch model.pomodoroState {
            case .idle:
                Button("Start Focus Session") {
                    model.startPomodoro()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .running:
                VStack(spacing: 8) {
                    Text("Focusing... \(formatTime(model.remaining))")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    HStack {
                        Button("Pause") {
                            model.pauseSession()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Finish") {
                            model.finishSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .distracted:
                VStack(spacing: 8) {
                    Text("Distracted! \(formatTime(model.remaining))")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    HStack {
                        Button("Pause") {
                            model.pauseSession()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Finish") {
                            model.finishSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .success:
                Text("Great work! 🎉")
                    .font(.headline)
                    .foregroundColor(.green)

            case .breakTime:
                Text("Break time: \(formatTime(model.remaining))")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Stats:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Focused: \(formatTime(model.focusedSecondsToday))")
                    Spacer()
                    Text("Distracted: \(formatTime(model.distractedSecondsToday))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Divider()

            // App & Website Management
            DisclosureGroup("Allowed Apps & Sites") {
                VStack(alignment: .leading, spacing: 8) {
                    // Running apps
                    Text("Apps:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let userApps = NSWorkspace.shared.runningApplications
                        .filter { $0.bundleIdentifier != nil && $0.activationPolicy == .regular }
                        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                    
                    ForEach(userApps, id: \.bundleIdentifier) { app in
                        if let bid = app.bundleIdentifier {
                            let allowed = model.globalAllowed.contains(bid)
                            Button(action: { model.toggleAppAllowed(bid) }) {
                                HStack {
                                    if allowed {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                    }
                                    Text(app.localizedName ?? bid)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Website rules
                    Text("Websites:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    HStack {
                        TextField("Add domain (e.g., github.com)", text: $newWebsite)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        
                        Button("Add") {
                            model.addWebsiteRule(newWebsite)
                            newWebsite = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    ForEach(model.webRules.indices, id: \.self) { idx in
                        let rule = model.webRules[idx]
                        HStack {
                            Toggle(isOn: Binding(get: { rule.enabled }, set: { _ in model.toggleRule(id: rule.id) })) {
                                Text(rule.domain)
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            Button("×") {
                                model.removeRule(id: rule.id)
                            }
                            .foregroundColor(.red)
                            .buttonStyle(.plain)
                            .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.vertical, 4)

            // Minimize/Show toggle
            Button(model.isMinimized ? "Show Robot" : "Hide Robot") {
                model.toggleMinimize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}

// Helper function to format time
private func formatTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

// MARK: - Robot View (Proper Cartoon Robot)
struct RobotView: View {
    @EnvironmentObject var model: BotModel

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            
            ZStack {
                // Main robot body using VectorRobotView
                let bodyColor: Color = {
                    switch model.pomodoroState {
                    case .distracted:
                        let brightness: Double = model.pulse ? 1.0 : 0.75
                        return Color(red: brightness, green: 0.1 * brightness, blue: 0.1 * brightness)
                    case .success:
                        return .green
                    default:
                        return Color(hue: model.bodyHue, saturation: 0.8, brightness: 0.9)
                    }
                }()

                VectorRobotView(blink: model.blink, state: model.pomodoroState, color: bodyColor)
                    .frame(width: size * 0.8)
                    .scaleEffect(
                        model.pomodoroState == .distracted ? (model.pulse ? 1.12 : 0.92) :
                        (model.pomodoroState == .running ? (model.pulse ? 1.02 : 0.98) : (model.blink ? 1.05 : 0.95))
                    )
                    .shadow(color: model.pomodoroState == .distracted ? Color.red.opacity(0.4) : Color.clear, radius: model.pomodoroState == .distracted ? 8 : 0)
                    .rotationEffect(.degrees(model.wiggleRotation))
                    .offset(model.wiggleOffset)
                    .animation(.easeInOut(duration: model.pomodoroState == .distracted ? 0.22 : 0.6), value: model.pulse)
                    .animation(.easeInOut(duration: 0.8), value: model.blink)

                // Timer display at bottom (hidden when distracted/angry)
                if model.pomodoroState == .running {
                    VStack {
                        Spacer()
                        simpleTimerView(
                            style: model.clockStyle,
                            remaining: model.remaining,
                            fontSize: model.fontSize,
                            bodyHue: model.bodyHue,
                            state: model.pomodoroState
                        )
                        .padding(.bottom, 10)
                    }
                } else if model.pomodoroState == .success {
                    VStack {
                        Spacer()
                        Text("✅")
                            .font(.system(size: 24))
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onTapGesture {
            if model.pomodoroState == .idle || model.pomodoroState == .success {
                model.startPomodoro()
            }
        }
    }
}

// MARK: - Clock rendering helpers (Simple)
private func timeString(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds/60, seconds%60)
}

@ViewBuilder
private func simpleTimerView(style: ClockStyle, remaining: Int, fontSize: CGFloat, bodyHue: Double, state: BotModel.PomodoroState) -> some View {
    switch style {
    case .numeric:
        Text(timeString(remaining))
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    case .dotMatrix:
        DotMatrixClockView(time: remaining, dotSize: max(2, fontSize * 0.12))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    case .gradient:
        let h1 = bodyHue
        let h2 = (bodyHue + 0.35).truncatingRemainder(dividingBy: 1.0)
        let label = Text(timeString(remaining))
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
        label
            .foregroundColor(.white.opacity(0.001))
            .overlay(
                LinearGradient(colors: [
                    Color(hue: h1, saturation: 0.85, brightness: 1.0),
                    Color(hue: h2, saturation: 0.85, brightness: 1.0)
                ], startPoint: .leading, endPoint: .trailing)
                .mask(label)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    case .neon:
        let base = (state == .distracted) ? Color.red : Color(hue: bodyHue, saturation: 0.9, brightness: 1.0)
        Text(timeString(remaining))
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(base)
            .shadow(color: base.opacity(0.9), radius: 8)
            .shadow(color: base.opacity(0.6), radius: 12)
            .shadow(color: base.opacity(0.3), radius: 16)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Dot-matrix clock components
private struct DotMatrixClockView: View {
    let time: Int
    let dotSize: CGFloat

    private var timeStringValue: String {
        String(format: "%02d:%02d", time/60, time%60)
    }

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(Array(timeStringValue), id: \.self) { ch in
                DotDigitView(character: ch, dotSize: dotSize)
            }
        }
    }
}

private struct DotDigitView: View {
    let character: Character
    let dotSize: CGFloat

    private static let patterns: [Character: [String]] = [
        "0": [
            "01110",
            "10001",
            "10011",
            "10101",
            "11001",
            "10001",
            "01110"
        ],
        "1": [
            "00100",
            "01100",
            "00100",
            "00100",
            "00100",
            "00100",
            "01110"
        ],
        "2": [
            "01110",
            "10001",
            "00001",
            "00010",
            "00100",
            "01000",
            "11111"
        ],
        "3": [
            "11110",
            "00001",
            "00001",
            "01110",
            "00001",
            "00001",
            "11110"
        ],
        "4": [
            "00010",
            "00110",
            "01010",
            "10010",
            "11111",
            "00010",
            "00010"
        ],
        "5": [
            "11111",
            "10000",
            "11110",
            "00001",
            "00001",
            "10001",
            "01110"
        ],
        "6": [
            "00110",
            "01000",
            "10000",
            "11110",
            "10001",
            "10001",
            "01110"
        ],
        "7": [
            "11111",
            "00001",
            "00010",
            "00100",
            "01000",
            "10000",
            "10000"
        ],
        "8": [
            "01110",
            "10001",
            "10001",
            "01110",
            "10001",
            "10001",
            "01110"
        ],
        "9": [
            "01110",
            "10001",
            "10001",
            "01111",
            "00001",
            "00010",
            "01100"
        ],
        ":": [
            "00000",
            "00100",
            "00100",
            "00000",
            "00100",
            "00100",
            "00000"
        ]
    ]

    var body: some View {
        let pattern = Self.patterns[character] ?? Self.patterns["0"]!
        VStack(spacing: dotSize * 0.5) {
            ForEach(0..<pattern.count, id: \.self) { r in
                HStack(spacing: dotSize * 0.5) {
                    let row = Array(pattern[r])
                    ForEach(0..<row.count, id: \.self) { c in
                        Circle()
                            .fill(row[c] == "1" ? Color.white : Color.white.opacity(0.15))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
    }
}

struct GradientText: View {
    let text: String
    let colors: [Color]
    var body: some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .mask(
                Text(text)
            )
    }
}

struct NeonGlowText: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .foregroundColor(color)
            .shadow(color: color.opacity(0.9), radius: 8)
            .shadow(color: color.opacity(0.6), radius: 12)
            .shadow(color: color.opacity(0.3), radius: 16)
    }
}

// MARK: - Vector Robot (Proper Cartoon Design)
struct VectorRobotView: View {
    var blink: Bool
    var state: BotModel.PomodoroState
    var color: Color
    
    private var eyeWidth: CGFloat {
        switch state {
        case .distracted: return 14
        default: return blink ? 18 : 12
        }
    }
    
    private var eyeHeight: CGFloat {
        switch state {
        case .distracted: return 4
        default: return blink ? 2 : 12
        }
    }
    
    private var mouth: some View {
        switch state {
        case .success:
            return AnyView(Capsule().stroke(Color.white, lineWidth: 2)
                            .frame(width: 36, height: 12)
                            .offset(y: 12))
        case .distracted:
            return AnyView(Path { path in
                path.move(to: CGPoint(x: -18, y: 0))
                path.addQuadCurve(to: CGPoint(x: 18, y: 0), control: CGPoint(x: 0, y: -12))
            }
            .stroke(Color.white, lineWidth: 4)
            .frame(width: 36, height: 16)
            .offset(x: 18, y: 30))
        default:
            return AnyView(Capsule().fill(Color.white.opacity(0.7))
                            .frame(width: 24, height: 4)
                            .offset(y: 12))
        }
    }

    var body: some View {
        ZStack {
            // Robot head (main body)
            RoundedRectangle(cornerRadius: 20)
                .fill(color)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )

            // Robot eyes (hidden when distracted for closed-eye look)
            if state != .distracted {
                HStack(spacing: 16) {
                    // Left eye
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: eyeWidth, height: eyeHeight)
                        .overlay(
                            Circle()
                                .fill(Color.black)
                                .frame(width: blink ? 0 : 6, height: blink ? 0 : 6)
                        )
                        .offset(y: -8)
                    
                    // Right eye
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: eyeWidth, height: eyeHeight)
                        .overlay(
                            Circle()
                                .fill(Color.black)
                                .frame(width: blink ? 0 : 6, height: blink ? 0 : 6)
                        )
                        .offset(y: -8)
                }
            }

            // Angry eyebrows (only when distracted)
            if state == .distracted {
                HStack(spacing: 14) {
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 22, height: 4)
                        .rotationEffect(.degrees(28))
                    Capsule()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 22, height: 4)
                        .rotationEffect(.degrees(-28))
                }
                .offset(y: -10)
            }

            // Robot mouth
            mouth

            // Robot antennas (dual, explicitly positioned)
            Group {
                // Left antenna
                VStack {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: 10)
                    Spacer()
                }
                .offset(x: -18, y: -10)
                .zIndex(1)
                
                // Right antenna
                VStack {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: 10)
                    Spacer()
                }
                .offset(x: 18, y: -10)
                .zIndex(1)
            }

            // Robot arms
            HStack(spacing: 100) {
                // Left arm
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.8))
                    .frame(width: 16, height: 40)
                    .offset(y: 10)
                
                // Right arm
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.8))
                    .frame(width: 16, height: 40)
                    .offset(y: 10)
            }

            // Robot body/chest panel
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 30)
                .offset(y: 20)
        }
        .frame(width: 110, height: 120) // enlarge bounds to show antennas
        .animation(.easeInOut(duration: 0.2), value: blink)
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

// MARK: - App Entry
@main
struct BotPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var model: BotModel
    private let controller: BotPanelController

    init() {
        let m = BotModel()
        _model = StateObject(wrappedValue: m)
        controller = BotPanelController(model: m)
    }

    var body: some Scene {
        MenuBarExtra(menuBarTitle, systemImage: "brain.head.profile") {
            BotMenuView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
    
    private var menuBarTitle: String {
        if model.pomodoroState == .running || model.pomodoroState == .distracted || model.pomodoroState == .breakTime {
            return formatTime(model.remaining)
        } else {
            return "FocusdBot Simple"
        }
    }
}

extension Int {
    fileprivate func nonZeroOrDefault(_ def: Int) -> Int { self == 0 ? def : self }
}

extension Double {
    fileprivate func nonZeroOrDefault(_ def: Double) -> Double { self == 0 ? def : self }
}

// Helper to show a timer-only item in the macOS status bar
final class StatusBarTimer {
    static let shared = StatusBarTimer()
    private var item: NSStatusItem?
    private init() {}

    @MainActor
    func update(text: String?) {
        if let text = text {
            if item == nil { item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
            guard let button = item?.button else { return }
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.image = nil
            button.title = text
            button.toolTip = "Focus time remaining"
        } else {
            if let item = item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }
}

// App delegate to run as accessory (no dock icon) and keep alive
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

// MARK: - Color extension for random colors
extension Color {
    static var random: Color {
        Color(
            red: Double.random(in: 0...1),
            green: Double.random(in: 0...1),
            blue: Double.random(in: 0...1)
        )
    }
}

// MARK: - Notification names
extension Notification.Name {
    static let botMinimizeToggled = Notification.Name("botMinimizeToggled")
    static let botShowPanel = Notification.Name("botShowPanel")
    static let botHidePanel = Notification.Name("botHidePanel")
}
