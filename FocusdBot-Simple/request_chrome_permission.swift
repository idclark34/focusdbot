import Foundation
import AppKit

print("Requesting Chrome automation permission...")

let scriptSource = """
tell application "Google Chrome"
    return URL of active tab of front window
end tell
"""

var error: NSDictionary?
if let script = NSAppleScript(source: scriptSource) {
    let result = script.executeAndReturnError(&error)
    if let err = error {
        print("ERROR: \(err)")
        print("\nYou need to grant automation permission!")
        print("Go to: System Settings → Privacy & Security → Automation")
    } else if let urlString = result.stringValue {
        print("SUCCESS! Got URL: \(urlString)")
    }
}
