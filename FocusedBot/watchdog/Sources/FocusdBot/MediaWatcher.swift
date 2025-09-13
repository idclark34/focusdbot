import Foundation
import AppKit

final class MediaWatcher {
    private var notifications: [BufferedEvent] = []
    private var observers: [NSObjectProtocol] = []
    
    func startMonitoring() {
        let center = DistributedNotificationCenter.default()
        let itunes = center.addObserver(forName: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil, queue: .main) { [weak self] note in
            self?.handle(userInfo: note.userInfo, source: "iTunes")
        }
        let spotify = center.addObserver(forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            self?.handle(userInfo: note.userInfo, source: "Spotify")
        }
        observers = [itunes, spotify]
    }
    
    func stopMonitoring() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }
    
    func getBufferedEvents() -> [BufferedEvent] { notifications }
    func clearBufferedEvents() { notifications.removeAll() }
    
    private func handle(userInfo: [AnyHashable: Any]?, source: String) {
        guard let info = userInfo,
              let state = info["Player State"] as? String,
              state == "Playing",
              let name = info["Name"] as? String else { return }
        let artist = (info["Artist"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        let detail = [artist, album].filter { !$0.isEmpty }.joined(separator: " – ")
        notifications.append(BufferedEvent(timestamp: Date(), kind: "media", title: name, detail: detail))
    }
}