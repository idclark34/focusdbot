import Foundation
import AppKit

enum Chrome {
    /// Gets the URL of the active tab in Chrome, if available.
    /// Returns `nil` if Chrome is not running or has no open window.
    static func activeTabURL() -> URL? {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.google.Chrome"
        }) else {
            return nil
        }
        
        let scriptSource = """
        tell application "Google Chrome"
            try
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end try
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let result = script.executeAndReturnError(&error)
            if let output = result.stringValue, !output.isEmpty {
                return URL(string: output)
            }
        }
        
        return nil
    }
}
