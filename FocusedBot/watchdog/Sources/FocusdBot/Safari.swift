import Foundation
import AppKit

enum Safari {
    /// Gets the URL of the frontmost tab in Safari, if available.
    /// Returns `nil` if Safari is not running or has no open window.
    static func frontmostTabURL() -> URL? {
        guard let safari = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.Safari"
        }) else {
            return nil
        }
        
        let scriptSource = """
        tell application "Safari"
            if (count of windows) > 0 then
                return URL of front document
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            if let output = script.executeAndReturnError(&error).stringValue {
                return URL(string: output)
            }
        }
        
        return nil
    }
} 