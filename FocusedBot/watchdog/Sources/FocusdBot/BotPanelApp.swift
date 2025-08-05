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
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success, let win = window {
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success, let t = title as? String {
            return (bundleId, t)
        }
    }
    return (bundleId, "(no title)")
}

// MARK: - ViewModel (lightweight)
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

    private let phoneWatcher = PhoneWatcher()

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

    // Dashboard window
    private var dashboardController: DashboardWindowController?

    func showDashboard() {
        if dashboardController == nil {
            dashboardController = DashboardWindowController(model: self)
        }
        dashboardController?.toggle()
    }

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

    private var timer: Timer?
    private var activationObserver: Any?

    init() {
        // main tick (1-sec)
        loadWebRules()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // pulse timer (0.35-sec)
        _ = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.pulse.toggle()
        }

        // App activation observer for instant reaction
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundle = app.bundleIdentifier else { return }

            let allowed = bundle == self.selfBundle || self.sessionAllowedBundles.contains(bundle) || self.globalAllowed.contains(bundle)

            switch self.pomodoroState {
            case .running where !allowed:
                self.pomodoroState = .distracted
            case .distracted where allowed:
                self.pomodoroState = .running
            default:
                break
            }
        }
    }

    deinit {
        if let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

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
            let dx = Double.random(in: -4...4)
            let dy = Double.random(in: -4...4)
            wiggleOffset = CGSize(width: dx, height: dy)
            wiggleRotation = Double.random(in: -6...6)
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

        // phone activity overrides allowed check
        let phoneBusy = phoneWatcher.phoneActive

        var reallyAllowed = allowed && !phoneBusy

        if currentBundle == "com.apple.Safari" {
            if let url = Safari.frontmostTabURL(), let host = url.host {
                let isWebsiteAllowed = webRules.contains { $0.enabled && host.hasSuffix($0.domain) }
                reallyAllowed = isWebsiteAllowed
            } else {
                reallyAllowed = false // No URL, probably a new tab page
            }
        }

        switch pomodoroState {
        case .running:
            if !reallyAllowed {
                pomodoroState = .distracted
                return
            }
            remaining -= 1
            progress = 1.0 - Double(remaining) / Double(pomodoroTotal)
            focusedSecondsToday += 1 // count productive second
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
            }
            distractedSecondsToday += 1 // count distracted second
        case .breakTime:
            // countdown break
            remaining -= 1
            if remaining <= 0 {
                pomodoroState = .idle
                currentSessionId = nil
            }
        default:
            break
        }
    }

    // MARK: Website Permissions (rules)
    private let webRuleKey = "botWebRules"

    private func loadWebRules() {
        if let data = UserDefaults.standard.data(forKey: webRuleKey),
           let rules = try? JSONDecoder().decode([WebRule].self, from: data) {
            self.webRules = rules
        } else {
            // migrate old key if exists
            if let old = UserDefaults.standard.stringArray(forKey: "botAllowedWebsites") {
                self.webRules = old.map { WebRule(domain: $0, enabled: true) }
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
        let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

            let palette: [Color] = [.green, .blue, .orange, .purple, .pink]
            var idx = 0
            let slices: [AppSlice] = self.sessionAppSeconds
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { b, sec in
                    defer { idx += 1 }
                    return AppSlice(name: nameFor(b), seconds: sec, color: palette[idx % palette.count])
                }

            let controller = ReflectionWindowController(model: self, slices: slices)
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
    }

    // MARK: Allowed list handling
    func toggleGlobalAllowed(bundle: String) {
        if globalAllowed.contains(bundle) {
            globalAllowed.remove(bundle)
        } else {
            globalAllowed.insert(bundle)
        }
        UserDefaults.standard.set(Array(globalAllowed), forKey: "botGlobalAllowed")
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = size
        UserDefaults.standard.set(Double(size), forKey: "botFontSize")
    }
}

// MARK: - Pixel Robot View
struct PixelRobotView: View {
    var blink: Bool
    var state: BotModel.PomodoroState
    var hue: Double
    private let pixelSize: CGFloat = 6

    // 14x14 pixel sprite: 0 transparent, 1 body, 2 eye (white), 3 eye pupils (variable)
    private var sprite: [[Int]] {
        [
            [0,0,0,1,1,1,1,1,1,0,0,0,0,0],
            [0,0,1,2,2,1,1,2,2,1,0,0,0,0],
            [0,1,1,3,3,1,1,3,3,1,1,0,0,0],
            [0,1,1,1,1,1,1,1,1,1,1,0,0,0],
            [1,1,1,1,1,1,1,1,1,1,1,1,0,0],
            [1,1,1,1,1,1,1,1,1,1,1,1,0,0],
            [1,1,0,0,1,1,1,1,0,0,1,1,0,0],
            [1,1,0,0,1,1,1,1,0,0,1,1,0,0],
            [0,1,1,1,1,1,1,1,1,1,1,0,0,0],
            [0,0,1,1,0,0,0,0,1,1,0,0,0,0],
            [0,0,1,1,0,0,0,0,1,1,0,0,0,0],
            [0,0,1,1,0,0,0,0,1,1,0,0,0,0],
            [0,0,1,1,0,0,0,0,1,1,0,0,0,0],
            [0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        ]
    }

    private func color(for value: Int) -> Color {
        switch value {
        case 1:
            switch state {
            case .distracted: return .red
            case .success: return .green
            default: return Color(hue: hue, saturation: 0.8, brightness: 0.9)
            }
        case 2: return .white // eye whites
        case 3:
            if blink {
                // closed eyes: match body color for seamless lid
                switch state {
                case .distracted: return .red
                case .success: return .green
                default: return Color(red: 0.2, green: 0.7, blue: 0.9)
                }
            } else {
                return .black
            }
        default: return .clear
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<sprite.count, id: \ .self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<sprite[row].count, id: \ .self) { col in
                        Rectangle()
                            .fill(color(for: sprite[row][col]))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
        .id(state) // force redraw when state changes
    }
}

// MARK: - Confetti
struct ConfettiParticle: View {
    let color: Color
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 1

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .offset(offset)
            .onAppear {
                let dx = Double.random(in: -60...60)
                let dy = Double.random(in: 80...120)
                withAnimation(.easeOut(duration: 1.2)) {
                    offset = CGSize(width: dx, height: dy)
                    opacity = 0
                }
            }
    }
}

struct ConfettiView: View {
    let id: Int
    let ringSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \ .self) { idx in
                ConfettiParticle(color: Color(hue: Double(idx)/14.0, saturation: 0.8, brightness: 1.0))
                    .offset(x: 0, y: -ringSize*0.2)
            }
        }
        .id(id) // restart animation when id changes
    }
}

// MARK: - Robot View
struct RobotView: View {
    @EnvironmentObject var model: BotModel
    @Environment(\.colorScheme) private var colorScheme

    // Dynamic gradient based on state
    private var ringGradient: AngularGradient {
        switch model.pomodoroState {
        case .running:
            // Cool-tone sweep from green through teal to blue
            return AngularGradient(gradient: Gradient(colors: [.green, .teal, .blue]), center: .center)
        case .breakTime:
            return AngularGradient(gradient: Gradient(colors: [.cyan.opacity(0.5), .blue]), center: .center)
        case .distracted:
            return AngularGradient(gradient: Gradient(colors: [.orange, .red]), center: .center)
        default:
            return AngularGradient(gradient: Gradient(colors: [.gray]), center: .center)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let ringSize = min(geo.size.width, geo.size.height) * 1.0

            ZStack {
                // (Removed progress ring)

                // Robot sprite
                let isRest = model.pomodoroState == .breakTime
                let effectiveBlink = isRest ? true : model.blink
                let bobOffsetY = isRest ? (model.blink ? -ringSize * 0.02 : ringSize * 0.02) : 0

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

                VectorRobotView(blink: effectiveBlink, state: model.pomodoroState, color: bodyColor)
                    .frame(width: ringSize * 0.6)
                    .offset(x: 0, y: -ringSize * 0.03 + bobOffsetY)
                    .scaleEffect(model.pomodoroState == .distracted ? (model.pulse ? 1.05 : 0.95) : (isRest ? (model.blink ? 1.02 : 0.98) : (model.blink ? 1.05 : 0.95)))
                    .rotationEffect(.degrees(model.wiggleRotation))
                    .offset(model.wiggleOffset)
                    .animation(.easeInOut(duration: 0.35), value: model.pulse)
                    .animation(.easeInOut(duration: 0.8), value: model.blink)

                // Confetti overlay when success
                if model.pomodoroState == .success {
                    ConfettiView(id: model.confettiBurst, ringSize: ringSize)
                }

                // Timer / state icon at bottom
                VStack {
                    if model.pomodoroState == .running || model.pomodoroState == .breakTime || model.pomodoroState == .distracted {
                        timerView(for: model.clockStyle)
                    } else if model.pomodoroState == .success {
                        Text("✅")
                    }
                }
                .offset(y: ringSize * 0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // No extra padding or background so panel is tight around robot
        .onTapGesture(count: 1) {
            switch model.pomodoroState {
            case .idle, .success:
                model.startPomodoro()
            default:
                break // do nothing during running, break, or distracted
            }
        }
    }

    private func timeString(_ sec: Int) -> String {
        String(format: "%02d:%02d", sec/60, sec%60)
    }

    @ViewBuilder
    private func timerView(for style: ClockStyle) -> some View {
        switch style {
        case .numeric:
            Text(timeString(model.remaining))
                .font(.system(size: model.fontSize, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .minimumScaleFactor(0.5)
                .animation(.linear(duration: 1.0), value: model.bodyHue)
        case .gradient:
            let h1 = model.bodyHue
            let h2 = (model.bodyHue + 0.4).truncatingRemainder(dividingBy: 1.0)
            let colors = [Color(hue: h1, saturation: 0.8, brightness: 1.0),
                          Color(hue: h2, saturation: 0.8, brightness: 1.0)]
            GradientText(text: timeString(model.remaining), colors: colors)
                .font(.system(size: model.fontSize, design: .monospaced))
                .minimumScaleFactor(0.5)
                .animation(.linear(duration: 1.0), value: model.bodyHue)
        case .neon:
            let base = model.pomodoroState == .distracted ? Color.red : Color(hue: model.bodyHue, saturation: 0.8, brightness: 1.0)
            NeonGlowText(text: timeString(model.remaining), color: base)
                .font(.system(size: model.fontSize, design: .monospaced))
                .minimumScaleFactor(0.5)
        case .dotMatrix:
            DotMatrixClockView(time: model.remaining, dotSize: model.fontSize * 0.12)
        }
    }
}

// GradientText helper
struct GradientText: View {
    let text: String
    let colors: [Color]

    var body: some View {
        Text(text)
            .overlay(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            )
            .mask(Text(text))
    }
}

// MARK: - Panel Controller
final class BotPanelController {
    private var panel: NSPanel!
    private let model: BotModel

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
        print("[Bot] Panel constructed and ordering front…")
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // no scale observation
    }
}

// ==== NEW MENU CONTENT VIEW ====
struct BotMenuView: View {
    @EnvironmentObject var model: BotModel
    @State private var newWebsite: String = ""

    private var userApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Today stats card
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today")
                        .font(.title3.bold())
                    HStack(spacing: 12) {
                        stat(label: "Pomodoros", value: "\(model.completedToday)", symbol: "checkmark.circle.fill", color: .green)
                        stat(label: "Focus", value: "\(model.focusedSecondsToday / 60)m", symbol: "clock.fill", color: .blue)
                        stat(label: "Distracted", value: "\(model.distractedSecondsToday / 60)m", symbol: "exclamationmark.triangle.fill", color: .orange)
                    }
                }
                Divider()

                // Pomodoro duration section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pomodoro Duration")
                        .font(.subheadline.bold())
                    HStack {
                        ForEach([15, 25, 45, 60], id: \ .self) { minutes in
                            Button(action: { model.setDuration(minutes: minutes) }) {
                                Text("\(minutes)m")
                                    .fontWeight(minutes == model.durationMinutes ? .bold : .regular)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(minutes == model.durationMinutes ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Short test sessions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Test")
                        .font(.subheadline.bold())
                    HStack {
                        ForEach([15, 30], id: \ .self) { secs in
                            Button(action: { model.setTestDuration(secs) }) {
                                Text("\(secs)s")
                                    .fontWeight(model.testDurationSeconds == secs ? .bold : .regular)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(model.testDurationSeconds == secs ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: { model.setTestDuration(nil) }) {
                            Text("Off")
                                .fontWeight(model.testDurationSeconds == nil ? .bold : .regular)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(model.testDurationSeconds == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Clock style picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clock Style")
                        .font(.subheadline.bold())
                    HStack {
                        ForEach(ClockStyle.allCases) { style in
                            Button(action: { model.setClockStyle(style) }) {
                                Text(style.displayName)
                                    .fontWeight(model.clockStyle == style ? .bold : .regular)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(model.clockStyle == style ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Character picker removed – robot is now default

                // Allowed apps section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allowed Apps")
                        .font(.subheadline.bold())
                    ForEach(userApps, id: \ .bundleIdentifier) { app in
                        if let bid = app.bundleIdentifier {
                            let allowed = model.globalAllowed.contains(bid)
                            Button(action: { model.toggleGlobalAllowed(bundle: bid) }) {
                                HStack {
                                    if allowed {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    Text(app.localizedName ?? bid)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Allowed websites section
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allowed Websites")
                        .font(.subheadline.bold())

                    Button(action: {
                        if let url = Safari.frontmostTabURL(), let host = url.host {
                            model.addWebsiteRule(host)
                        }
                    }) {
                        Label("Bookmark Current Site in Safari", systemImage: "bookmark.fill")
                    }

                    HStack {
                        TextField("e.g. apple.com", text: $newWebsite)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            model.addWebsiteRule(newWebsite)
                            newWebsite = ""
                        }
                    }
                    ForEach(model.webRules.indices, id: \ .self) { idx in
                        let rule = model.webRules[idx]
                        HStack {
                            Toggle(isOn: Binding(get: { rule.enabled }, set: { _ in model.toggleRule(id: rule.id) })) {
                                Text(rule.domain)
                            }
                            .toggleStyle(.switch)
                            Spacer()
                            Button(action: { model.removeRule(id: rule.id) }) {
                                Image(systemName: "trash")
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // Recent reflections
                if !model.sessionSummaries.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Reflections")
                            .font(.subheadline.bold())
                        ForEach(model.sessionSummaries.prefix(5), id: \ .self) { item in
                            Text("• \(item)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()
                Button("Open Dashboard", action: { model.showDashboard() })
                    .padding(.vertical, 4)
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: 260, height: 380)
    }

    @ViewBuilder
    private func stat(label: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundColor(color)
                Text(value)
                    .font(.headline)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
        MenuBarExtra("FocusdBot", systemImage: "brain.head.profile") {
            BotMenuView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

extension Int {
    fileprivate func nonZeroOrDefault(_ def: Int) -> Int { self == 0 ? def : self }
}

extension Double {
    fileprivate func nonZeroOrDefault(_ def: Double) -> Double { self == 0 ? def : self }
}

// App delegate to run as accessory (no dock icon) and keep alive
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
} 

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
            // Head
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
                .frame(width: 120, height: 100)
            // Eyes
            HStack(spacing: 28) {
                RoundedRectangle(cornerRadius: eyeHeight/2)
                    .fill(Color.white)
                    .frame(width: eyeWidth, height: eyeHeight)
                    .rotationEffect(state == .distracted ? .degrees(20) : .zero)
                RoundedRectangle(cornerRadius: eyeHeight/2)
                    .fill(Color.white)
                    .frame(width: eyeWidth, height: eyeHeight)
                    .rotationEffect(state == .distracted ? .degrees(-20) : .zero)
            }
            .offset(y: -6)

            // Mouth
            mouth
            // Antenna
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .scaleEffect(blink ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.8), value: blink)
                Rectangle()
                    .fill(color)
                    .frame(width: 4, height: 20)
            }
            .offset(y: -70)
        }
        .frame(width: 140, height: 140)
    }
} 

// Neon glow text
struct NeonGlowText: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .foregroundColor(color)
            .shadow(color: color.opacity(0.9), radius: 8, x: 0, y: 0)
            .shadow(color: color.opacity(0.6), radius: 16, x: 0, y: 0)
    }
} 

// Dot-matrix clock view (5x7 per digit)
struct DotMatrixClockView: View {
    @Environment(\.colorScheme) private var cs
    let time: Int
    let dotSize: CGFloat

    private var chars: [Character] {
        Array(String(format: "%02d:%02d", time/60, time%60))
    }

    private var dotColor: Color { .white }

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(Array(chars.enumerated()), id: \ .offset) { idx, ch in
                if ch == ":" {
                    VStack(spacing: dotSize) {
                        Circle().fill(dotColor).frame(width: dotSize, height: dotSize)
                        Circle().fill(dotColor).frame(width: dotSize, height: dotSize)
                    }
                } else {
                    DotMatrixDigit(char: ch, dot: dotSize, color: dotColor)
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct DotMatrixDigit: View {
    let char: Character
    let dot: CGFloat
    let color: Color

    private static let patterns: [Character: [String]] = [
        "0": [
            "11111",
            "10001",
            "10011",
            "10101",
            "11001",
            "10001",
            "11111"
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
            "11111",
            "00001",
            "00001",
            "11111",
            "10000",
            "10000",
            "11111"
        ],
        "3": [
            "11111",
            "00001",
            "00001",
            "01111",
            "00001",
            "00001",
            "11111"
        ],
        "4": [
            "10001",
            "10001",
            "10001",
            "11111",
            "00001",
            "00001",
            "00001"
        ],
        "5": [
            "11111",
            "10000",
            "10000",
            "11111",
            "00001",
            "00001",
            "11111"
        ],
        "6": [
            "11111",
            "10000",
            "10000",
            "11111",
            "10001",
            "10001",
            "11111"
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
            "11111",
            "10001",
            "10001",
            "11111",
            "10001",
            "10001",
            "11111"
        ],
        "9": [
            "11111",
            "10001",
            "10001",
            "11111",
            "00001",
            "00001",
            "11111"
        ]
    ]

    var body: some View {
        let pattern = DotMatrixDigit.patterns[char] ?? Array(repeating: "00000", count: 7)
        VStack(spacing: dot * 0.4) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: dot * 0.4) {
                    ForEach(0..<5, id: \.self) { col in
                        if pattern[row][pattern[row].index(pattern[row].startIndex, offsetBy: col)] == "1" {
                            Circle().fill(color).frame(width: dot, height: dot)
                        } else {
                            Circle().fill(Color.clear).frame(width: dot, height: dot)
                        }
                    }
                }
            }
        }
    }
} 