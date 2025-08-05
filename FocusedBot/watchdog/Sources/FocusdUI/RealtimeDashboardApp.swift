import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Helper to fetch front-most window title
private func activeWindowInfo() -> (bundle: String, title: String) {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return ("(none)", "No active application")
    }
    let bundleId = app.bundleIdentifier ?? app.localizedName ?? "unknown"
    let pid = app.processIdentifier
    let axApp = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
       let win = window {
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
           let t = title as? String {
            return (bundleId, t)
        }
    }
    return (bundleId, "(no title)")
}

// MARK: - View Model
class RealtimeModel: ObservableObject {
    struct Span: Identifiable {
        let id = UUID()
        let bundleId: String
        let title: String
        let start: Date
    }

    @Published var currentBundle: String = ""
    @Published var currentTitle: String = ""
    @Published var recentSpans: [Span] = []
    @Published var keystrokesLastMinute: Int = 0

    // MARK: Pomodoro
    enum PomodoroState: String {
        case idle, running, success, distracted, breakTime
    }

    @Published var pomodoroState: PomodoroState = .idle
    @Published var pomodoroRemaining: Int = 25 * 60 // 25-minute session default

    private var pomodoroAllowedBundles: Set<String> = []

    func startPomodoro() {
        guard pomodoroState == .idle || pomodoroState == .success || pomodoroState == .distracted else { return }
        pomodoroAllowedBundles = [currentBundle]
        pomodoroRemaining = 25 * 60
        pomodoroState = .running
    }

    func stopPomodoro() {
        pomodoroState = .idle
    }

    private var inputTimestamps: [Date] = [] // store recent key/mouse timestamps (≤60s)

    private var timer: Timer?

    init() {
        // start timer updates
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // event tap for input events (keys + mouse)
        setupEventTap()
    }

    deinit {
        timer?.invalidate()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    private func tick() {
        let info = activeWindowInfo()

        if info.bundle != currentBundle || info.title != currentTitle {
            // new span started
            recentSpans.insert(Span(bundleId: info.bundle, title: info.title, start: Date()), at: 0)
            // keep only last 10
            recentSpans = Array(recentSpans.prefix(10))
        }
        currentBundle = info.bundle
        currentTitle = info.title

        // purge input events older than 60 seconds
        let cutoff = Date().addingTimeInterval(-60)
        inputTimestamps.removeAll { $0 < cutoff }
        keystrokesLastMinute = inputTimestamps.count

        // Pomodoro handling
        if pomodoroState == .running {
            // Check distraction: switched to disallowed bundle ID
            if !pomodoroAllowedBundles.contains(info.bundle) {
                pomodoroState = .distracted
            } else {
                // countdown
                pomodoroRemaining -= 1
                if pomodoroRemaining <= 0 {
                    pomodoroState = .success
                }
            }
        }
    }

    // MARK: Input Event Tap
    private var eventTap: CFMachPort?
    private var runLoopSrc: CFRunLoopSource?

    private func setupEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let model = Unmanaged<RealtimeModel>.fromOpaque(refcon).takeUnretainedValue()
            model.recordInput()
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())) else {
            print("[RealtimeModel] Could not create event tap. Requires Input Monitoring permission.")
            return
        }
        eventTap = tap
        runLoopSrc = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSrc {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func recordInput() {
        inputTimestamps.append(Date())
    }
}

// MARK: - Views
struct ContentView: View {
    @EnvironmentObject var model: RealtimeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current App: \(model.currentBundle)").font(.headline)
            Text(model.currentTitle).font(.subheadline)
            Divider()
            Text("Keystrokes/clicks last minute: \(model.keystrokesLastMinute)")
            Divider()
            Text("Recent Windows:").bold()
            ForEach(model.recentSpans) { span in
                Text("\(span.start, formatter: dateFormatter) – \(span.bundleId): \(span.title)")
                    .font(.caption)
            }

            Divider()
            pomodoroSection
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
    }

    // Pomodoro UI Section
    private var pomodoroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pomodoro: ").bold()
                switch model.pomodoroState {
                case .idle:
                    Text("Idle")
                case .running:
                    Text("Running – \(formatTime(model.pomodoroRemaining))")
                        .monospacedDigit()
                case .success:
                    Text("✅ Completed! Great job!")
                case .distracted:
                    Text("😠 Distracted!")
                case .breakTime:
                    Text("Break")
                }
            }

            HStack {
                if model.pomodoroState == .idle || model.pomodoroState == .success || model.pomodoroState == .distracted {
                    Button("Start 25-min Focus") {
                        model.startPomodoro()
                    }
                } else if model.pomodoroState == .running {
                    Button("Stop") {
                        model.stopPomodoro()
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.timeStyle = .medium
        return df
    }
}

// MARK: - App
@main
struct RealtimeDashboardApp: App {
    @StateObject private var model = RealtimeModel()

    var body: some Scene {
        WindowGroup("Focusd Realtime Dashboard") {
            ContentView()
                .environmentObject(model)
        }
    }
} 