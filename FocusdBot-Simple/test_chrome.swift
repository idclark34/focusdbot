import Foundation
import AppKit

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
    if let err = error {
        print("Error: \(err)")
    } else if let urlString = result.stringValue {
        print("URL: \(urlString)")
    } else {
        print("No URL returned")
    }
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
