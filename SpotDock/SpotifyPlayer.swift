import Foundation
import SwiftUI
import AppKit
import Combine

struct LyricLine: Identifiable, Codable {
    var id = UUID()
    let timestamp: TimeInterval
    let text: String
}

struct SpotifyTrack: Identifiable, Codable {
    let id: String
    let name: String
    let artistName: String
    let albumArtURL: String
}

@MainActor
class SpotifyPlayer: ObservableObject {
    static let shared = SpotifyPlayer()

    @Published var trackName: String = "No Track"
    @Published var artistName: String = "Unknown Artist"
    @Published var albumArtURL: String = ""
    @Published var progress: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var volume: Int = 50
    @Published var isLoading: Bool = false
    @Published var isAuthenticated: Bool = true // Always true now
    @Published var error: String? = nil
    @Published var isRateLimited: Bool = false
    @Published var showLyrics: Bool = false
    @Published var syncedLyrics: [LyricLine] = []
    @Published var lyrics: String = ""
    @Published var deviceName: String = "Local System"
    @Published var isShuffled: Bool = false
    @Published var repeatMode: String = "off"
    @Published var recommendations: [SpotifyTrack] = []
    @Published var queue: [SpotifyTrack] = []
    
    @AppStorage("useSystemNowPlaying") var useSystemNowPlaying: Bool = true
    @AppStorage("useUniversalNowPlaying") var useUniversalNowPlaying: Bool = true
    @AppStorage("showDynamicIsland") var showDynamicIsland: Bool = true
    @AppStorage("showMiniPlayer") var showMiniPlayer: Bool = true

    private var currentTrackID: String = ""
    private var pollingTimer: AnyCancellable?
    private var notificationObservers: [AnyCancellable] = []

    private init() {
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Listen for Spotify's internal playback state changes (Native system notifications)
        DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.spotify.client.PlaybackStateChanged"))
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchPlayerDataFromSystem()
                }
            }
            .store(in: &notificationObservers)
    }

    func startPolling() {
        pollingTimer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.fetchPlayerDataFromSystem()
                }
            }
    }

    func fetchPlayerDataFromSystem() async {
        let scriptSource = """
        try
            if application "Spotify" is running then
                tell application "Spotify"
                    set track_name to name of current track
                    set artist_name to artist of current track
                    set album_name to album of current track
                    set track_id to id of current track
                    set player_state to player state as string
                    set track_duration to duration of current track
                    set track_position to player position
                    set art_url to artwork url of current track
                    set is_shuffled to shuffling
                    set repeat_mode to repeating
                    return track_name & "||" & artist_name & "||" & album_name & "||" & track_id & "||" & player_state & "||" & track_duration & "||" & track_position & "||" & art_url & "||" & is_shuffled & "||" & repeat_mode
                end tell
            else
                return "Not Running"
            end if
        on error
            return "Error"
        end try
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let output = script.executeAndReturnError(&error)
            if error != nil { return }
            
            let resultString = output.stringValue ?? ""
            if resultString == "Not Running" || resultString == "Error" {
                DispatchQueue.main.async {
                    self.trackName = ""
                    self.artistName = ""
                    self.isPlaying = false
                }
                return
            }
            
            let parts = resultString.components(separatedBy: "||")
            if parts.count >= 10 {
                DispatchQueue.main.async {
                    self.trackName = parts[0]
                    self.artistName = parts[1]
                    let newTrackID = parts[3]
                    self.isPlaying = (parts[4].lowercased() == "playing")
                    self.duration = (Double(parts[5]) ?? 0) / 1000.0
                    self.progress = Double(parts[6]) ?? 0
                    self.albumArtURL = parts[7]
                    self.isShuffled = (parts[8].lowercased() == "true")
                    self.repeatMode = (parts[9].lowercased() == "true") ? "track" : "off"
                    
                    if newTrackID != self.currentTrackID && !newTrackID.isEmpty {
                        self.currentTrackID = newTrackID
                        Task {
                            await self.fetchLyrics(artist: parts[1], track: parts[0])
                        }
                    }
                    
                    self.updateSystemVolume()
                    self.error = nil
                }
            }
        }
    }

    func fetchLyrics(artist: String, track: String) async {
        guard !artist.isEmpty && !track.isEmpty else { return }
        
        // Clean up common suffixes that break lyrics searches
        let cleanTrack = track.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)
                             .replacingOccurrences(of: "\\s*\\[.*?\\]", with: "", options: .regularExpression)
                             .trimmingCharacters(in: .whitespaces)
        
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedTrack = cleanTrack.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://lrclib.net/api/get?artist_name=\(encodedArtist)&track_name=\(encodedTrack)"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    if let syncedLRC = json["syncedLyrics"] as? String {
                        self.syncedLyrics = self.parseLRC(syncedLRC)
                        self.lyrics = ""
                    } else if let plainLyrics = json["plainLyrics"] as? String {
                        self.lyrics = plainLyrics
                        self.syncedLyrics = []
                    } else {
                        self.lyrics = ""
                        self.syncedLyrics = []
                    }
                }
            }
        } catch {
            print("❌ Error fetching lyrics: \(error)")
        }
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d+):(\\d+\\.?\\d*)\\](.*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        let lrcLines = lrc.components(separatedBy: .newlines)
        for line in lrcLines {
            let nsString = line as NSString
            let results = regex?.matches(in: line, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            
            for match in results {
                if match.numberOfRanges >= 4 {
                    let minStr = nsString.substring(with: match.range(at: 1))
                    let secStr = nsString.substring(with: match.range(at: 2))
                    let text = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    
                    if let minutes = Double(minStr), let seconds = Double(secStr) {
                        let timestamp = minutes * 60 + seconds
                        lines.append(LyricLine(timestamp: timestamp, text: text))
                    }
                }
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private func updateSystemVolume() {
        let scriptSource = "output volume of (get volume settings)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                self.volume = Int(result.int32Value)
            }
        }
    }

    // Playback Controls via AppleScript (Works for Free accounts)
    func togglePlay() {
        runScript("tell application \"Spotify\" to playpause")
    }

    func nextTrack() {
        runScript("tell application \"Spotify\" to next track")
    }

    func previousTrack() {
        runScript("tell application \"Spotify\" to previous track")
    }

    func toggleShuffle() async {
        runScript("tell application \"Spotify\" to set shuffling to not shuffling")
    }

    func toggleRepeat() async {
        runScript("tell application \"Spotify\" to set repeating to not repeating")
    }

    func seek(to position: TimeInterval) {
        runScript("tell application \"Spotify\" to set player position to \(position)")
    }
    
    private func runScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
    
    func logout() {
        // No-op now
    }
}
