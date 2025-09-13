import Foundation
import AppKit
import ApplicationServices

struct BufferedEvent {
    let timestamp: Date
    let kind: String
    let title: String
    let detail: String?
}

final class ActivityMonitor {
    private var timer: Timer?
    private var buffer: [BufferedEvent] = []
    private var lastBundle: String?
    private var lastTitle: String?
    
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    func startMonitoring() {
        // Check permissions first
        if !Self.checkAccessibilityPermission() {
            print("[ActivityMonitor] Accessibility permission not granted")
            Self.requestAccessibilityPermission()
            return
        }
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func getBufferedEvents() -> [BufferedEvent] { buffer }
    func clearBufferedEvents() { buffer.removeAll() }
    
    private func poll() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundle = app.bundleIdentifier ?? "unknown"
        let title = activeWindowTitle(pid: app.processIdentifier) ?? ""
        guard bundle != lastBundle || title != lastTitle else { return }
        lastBundle = bundle
        lastTitle = title
        buffer.append(BufferedEvent(timestamp: Date(), kind: "app", title: bundle, detail: title))
    }
    
    private func activeWindowTitle(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) != .success { return nil }
        guard let win = window else { return nil }
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success {
            return title as? String
        }
        return nil
    }
}