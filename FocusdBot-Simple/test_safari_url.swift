import Foundation
import AppKit

let scriptSource = """
tell application "Safari"
    if (count of windows) > 0 then
        return URL of front document
    end if
end tell
"""

var error: NSDictionary?
if let script = NSAppleScript(source: scriptSource) {
    let result = script.executeAndReturnError(&error)
    if let err = error {
        print("Error: \(err)")
    } else if let urlString = result.stringValue {
        print("URL: \(urlString)")
        if let url = URL(string: urlString), let host = url.host {
            print("Host: \(host)")
        }
    } else {
        print("No URL returned")
    }
}

RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
