import Foundation
import AppKit

// MARK: - Media Watcher
final class MediaWatcher: ObservableObject {
    private var bufferedEvents: [BufferedEvent] = []
    
    // Published state for UI
    @Published var isMonitoring: Bool = false
    @Published var currentTrack: String?
    @Published var currentArtist: String?
    
    // Notification observers
    private var iTunesObserver: NSObjectProtocol?
    private var spotifyObserver: NSObjectProtocol?
    
    init() {
        // Initialize but don't start monitoring yet
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Interface
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        bufferedEvents.removeAll()
        
        setupNotificationObservers()
        
        print("[MediaWatcher] Started monitoring")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        removeNotificationObservers()
        
        print("[MediaWatcher] Stopped monitoring. Buffered \(bufferedEvents.count) events")
    }
    
    func getBufferedEvents() -> [BufferedEvent] {
        return bufferedEvents
    }
    
    func clearBufferedEvents() {
        bufferedEvents.removeAll()
    }
    
    // MARK: - Private Implementation
    
    private func setupNotificationObservers() {
        let notificationCenter = DistributedNotificationCenter.default()
        
        // iTunes/Music app notifications
        iTunesObserver = notificationCenter.addObserver(
            forName: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] notification in
            self?.handleiTunesNotification(notification)
        }
        
        // Spotify notifications
        spotifyObserver = notificationCenter.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] notification in
            self?.handleSpotifyNotification(notification)
        }
    }
    
    private func removeNotificationObservers() {
        let notificationCenter = DistributedNotificationCenter.default()
        
        if let observer = iTunesObserver {
            notificationCenter.removeObserver(observer)
            iTunesObserver = nil
        }
        
        if let observer = spotifyObserver {
            notificationCenter.removeObserver(observer)
            spotifyObserver = nil
        }
    }
    
    private func handleiTunesNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let playerState = userInfo["Player State"] as? String
        let name = userInfo["Name"] as? String
        let artist = userInfo["Artist"] as? String
        let album = userInfo["Album"] as? String
        
        // Only track when actually playing
        guard playerState == "Playing",
              let trackName = name,
              !trackName.isEmpty else { return }
        
        let artistInfo = artist ?? "Unknown Artist"
        let albumInfo = album ?? "Unknown Album"
        let detail = "\(artistInfo) – \(albumInfo)"
        
        let event = BufferedEvent(
            kind: "media",
            title: trackName,
            detail: detail
        )
        
        bufferedEvents.append(event)
        
        // Update published properties
        currentTrack = trackName
        currentArtist = artistInfo
        
        print("[MediaWatcher] iTunes/Music: \(trackName) by \(artistInfo)")
    }
    
    private func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        let playerState = userInfo["Player State"] as? String
        let trackId = userInfo["Track ID"] as? String
        
        // Only track when actually playing
        guard playerState == "Playing",
              let _ = trackId else { return }
        
        // For Spotify, we need to get current track info via AppleScript
        // since the notification doesn't contain track details
        getSpotifyTrackInfo { [weak self] trackInfo in
            guard let self = self,
                  let info = trackInfo else { return }
            
            let detail = "\(info.artist) – \(info.album)"
            
            let event = BufferedEvent(
                kind: "media",
                title: info.name,
                detail: detail
            )
            
            self.bufferedEvents.append(event)
            
            // Update published properties
            DispatchQueue.main.async {
                self.currentTrack = info.name
                self.currentArtist = info.artist
            }
            
            print("[MediaWatcher] Spotify: \(info.name) by \(info.artist)")
        }
    }
    
    // MARK: - Spotify Track Info via AppleScript
    
    private struct SpotifyTrackInfo {
        let name: String
        let artist: String
        let album: String
    }
    
    private func getSpotifyTrackInfo(completion: @escaping (SpotifyTrackInfo?) -> Void) {
        let script = """
            tell application "Spotify"
                if it is running then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "|||" & trackArtist & "|||" & trackAlbum
                end if
            end tell
        """
        
        DispatchQueue.global(qos: .background).async {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                if let error = error {
                    print("[MediaWatcher] Spotify AppleScript error: \(error)")
                    completion(nil)
                    return
                }
                
                guard let resultString = result?.stringValue else {
                    completion(nil)
                    return
                }
                
                let components = resultString.components(separatedBy: "|||")
                guard components.count == 3 else {
                    completion(nil)
                    return
                }
                
                let trackInfo = SpotifyTrackInfo(
                    name: components[0],
                    artist: components[1],
                    album: components[2]
                )
                
                completion(trackInfo)
            }
        }
    }
}