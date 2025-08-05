import Foundation
import AppKit
import ApplicationServices

// MARK: - Buffered Event
struct BufferedEvent {
    let timestamp: Date
    let kind: String
    let title: String
    let detail: String?
    
    init(kind: String, title: String, detail: String? = nil) {
        self.timestamp = Date()
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

// MARK: - Activity Monitor
final class ActivityMonitor: ObservableObject {
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "ActivityMonitor.timer", qos: .background)
    
    // Buffered events during session
    private var bufferedEvents: [BufferedEvent] = []
    
    // Track previous state to detect changes
    private var lastBundleId: String?
    private var lastWindowTitle: String?
    
    // Published state for UI
    @Published var isMonitoring: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    
    init() {
        checkAccessibilityPermission()
    }
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        checkAccessibilityPermission()
        
        if !hasAccessibilityPermission {
            showAccessibilityPermissionAlert()
            return
        }
        
        isMonitoring = true
        bufferedEvents.removeAll()
        
        // Initialize current state
        updateCurrentState()
        
        // Start timer
        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer?.schedule(deadline: .now() + 5.0, repeating: 5.0) // Every 5 seconds
        timer?.setEventHandler { [weak self] in
            self?.updateCurrentState()
        }
        timer?.resume()
        
        print("[ActivityMonitor] Started monitoring")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        timer?.cancel()
        timer = nil
        
        print("[ActivityMonitor] Stopped monitoring. Buffered \(bufferedEvents.count) events")
    }
    
    func getBufferedEvents() -> [BufferedEvent] {
        return bufferedEvents
    }
    
    func clearBufferedEvents() {
        bufferedEvents.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    private func showAccessibilityPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                FocusdBot needs Accessibility permission to track which applications you're using during focus sessions.
                
                Please:
                1. Open System Settings
                2. Go to Privacy & Security → Accessibility  
                3. Enable FocusdBot
                4. Restart the app
                
                This permission allows the app to create detailed session summaries.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Skip")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open Accessibility settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    private func updateCurrentState() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        let bundleId = app.bundleIdentifier ?? app.localizedName ?? "unknown"
        let windowTitle = getActiveWindowTitle() ?? "(no title)"
        
        // Check if anything changed
        if bundleId != lastBundleId || windowTitle != lastWindowTitle {
            // Buffer the new event
            let event = BufferedEvent(
                kind: "app",
                title: bundleId,
                detail: windowTitle
            )
            
            bufferedEvents.append(event)
            
            // Update tracking variables
            lastBundleId = bundleId
            lastWindowTitle = windowTitle
            
            print("[ActivityMonitor] App changed: \(bundleId) - \(windowTitle)")
        }
    }
    
    private func getActiveWindowTitle() -> String? {
        guard hasAccessibilityPermission,
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
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
}