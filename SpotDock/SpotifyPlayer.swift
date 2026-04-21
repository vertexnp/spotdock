import Foundation
import SwiftUI
import AuthenticationServices
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
    @Published var isAuthenticated: Bool = false
    @Published var error: String? = nil
    @Published var isRateLimited: Bool = false
    @Published var showLyrics: Bool = false
    @Published var syncedLyrics: [LyricLine] = []
    @Published var lyrics: String = ""
    @Published var deviceName: String = ""
    @Published var isShuffled: Bool = false
    @Published var repeatMode: String = "off" // off, track, context
    @Published var recommendations: [SpotifyTrack] = []
    @Published var queue: [SpotifyTrack] = []
    @AppStorage("useSystemNowPlaying") var useSystemNowPlaying: Bool = false
    @AppStorage("useUniversalNowPlaying") var useUniversalNowPlaying: Bool = true
    @AppStorage("showDynamicIsland") var showDynamicIsland: Bool = true
    @AppStorage("showMiniPlayer") var showMiniPlayer: Bool = true

    private var currentTrackID: String = ""
    private var pollingTimer: AnyCancellable?
    private let clientID = EnvironmentManager.shared.get("SPOTIFY_CLIENT_ID") ?? ""
    private let clientSecret = EnvironmentManager.shared.get("SPOTIFY_CLIENT_SECRET") ?? ""
    private var accessToken: String? = nil
    private var refreshToken: String?

    private var notificationObservers: [AnyCancellable] = []

    private init() {
        if let savedToken = UserDefaults.standard.string(forKey: "SpotifyRefreshToken") {
            self.refreshToken = savedToken
            self.isAuthenticated = true
        } else if let envToken = EnvironmentManager.shared.get("SPOTIFY_REFRESH_TOKEN"), !envToken.isEmpty {
            self.refreshToken = envToken
            self.isAuthenticated = true
        }
        
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Listen for Spotify's internal playback state changes (bypasses polling for immediate updates)
        DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.spotify.client.PlaybackStateChanged"))
            .sink { [weak self] _ in
                Task { [weak self] in
                    if self?.useSystemNowPlaying == true {
                        await self?.fetchPlayerDataFromSystem()
                    } else {
                        await self?.refreshPlayerData()
                    }
                }
            }
            .store(in: &notificationObservers)
    }

    func startPolling() {
        // Reduced frequency from 1s to 5s since notifications handle immediate changes
        pollingTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    guard let self = self else { return }
                    if self.useSystemNowPlaying {
                        await self.fetchPlayerDataFromSystem()
                    } else {
                        await self.refreshPlayerData()
                    }
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
                    return track_name & "||" & artist_name & "||" & album_name & "||" & track_id & "||" & player_state & "||" & track_duration & "||" & track_position & "||" & art_url
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
            if let error = error {
                print("🍎 [System] AppleScript Error: \(error)")
                // Only clear error if we are not forcing system and it's a "real" error
                if !useSystemNowPlaying { await refreshPlayerData() }
                return
            }
            
            let resultString = output.stringValue ?? ""
            if resultString == "Not Running" {
                DispatchQueue.main.async {
                    self.trackName = "Spotify Not Running"
                    self.artistName = ""
                    self.isPlaying = false
                }
                return
            } else if resultString == "Error" {
                // Spotify is likely running but nothing is playing or we don't have permission yet
                DispatchQueue.main.async {
                    self.trackName = "Nothing Playing"
                    self.artistName = "Open Spotify"
                    self.isPlaying = false
                }
                return
            }
            
            let parts = resultString.components(separatedBy: "||")
            if parts.count >= 8 {
                DispatchQueue.main.async {
                    self.trackName = parts[0]
                    self.artistName = parts[1]
                    // albumName is parts[2]
                    let newTrackID = parts[3]
                    self.isPlaying = (parts[4].lowercased() == "playing")
                    self.duration = (Double(parts[5]) ?? 0) / 1000.0
                    self.progress = Double(parts[6]) ?? 0
                    self.albumArtURL = parts[7]
                    
                    if newTrackID != self.currentTrackID && !newTrackID.isEmpty {
                        self.currentTrackID = newTrackID
                        Task {
                            await self.fetchLyrics(artist: self.artistName, track: self.trackName)
                        }
                    }
                    
                    // Fetch system volume
                    self.updateSystemVolume()
                    
                    self.isRateLimited = false
                    self.error = nil
                }
            }
        }
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

    func login() {
        let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"
        let redirectURI = "spotdock://callback"
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        
        guard let authURL = components.url else { return }
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "spotdock") { callbackURL, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.error = "Auth Error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let callbackURL = callbackURL,
                  let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                return
            }
            
            Task {
                await self.exchangeCodeForToken(code: code, redirectURI: redirectURI)
            }
        }
        
        session.presentationContextProvider = AuthPresentationAnchor.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func exchangeCodeForToken(code: String, redirectURI: String) async {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        let authString = "\(clientID):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newToken = json["access_token"] as? String {
                self.accessToken = newToken
                let newRefreshToken = json["refresh_token"] as? String
                self.refreshToken = newRefreshToken
                
                if let tokenToSave = newRefreshToken {
                    UserDefaults.standard.set(tokenToSave, forKey: "SpotifyRefreshToken")
                }
                
                self.isAuthenticated = true
                if self.useSystemNowPlaying {
                    await fetchPlayerDataFromSystem()
                } else {
                    await refreshPlayerData()
                }
                startPolling()
            }
        } catch {
            self.error = "Token Exchange Failed: \(error.localizedDescription)"
        }
    }

    func logout() {
        isAuthenticated = false
        refreshToken = nil
        accessToken = nil
        UserDefaults.standard.removeObject(forKey: "SpotifyRefreshToken")
    }

    func refreshPlayerData() async {
        if useSystemNowPlaying {
            await fetchPlayerDataFromSystem()
            return
        }
        
        guard isAuthenticated else { return }

        if accessToken == nil {
            await refreshAccessToken()
        }

        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    self.error = nil
                    self.isRateLimited = false
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    updatePlaybackState(json)
                } else if httpResponse.statusCode == 204 {
                    self.trackName = "Nothing Playing"
                    self.artistName = ""
                    self.albumArtURL = ""
                    self.isPlaying = false
                    self.currentTrackID = ""
                    self.syncedLyrics = []
                    self.lyrics = ""
                } else if httpResponse.statusCode == 429 {
                    self.isRateLimited = true
                    await fetchPlayerDataFromSystem()
                } else if httpResponse.statusCode == 401 {
                    await refreshAccessToken()
                }
            }
        } catch {
            await fetchPlayerDataFromSystem()
        }
    }

    private func updatePlaybackState(_ json: [String: Any]?) {
        guard let json = json else { return }
        
        var newTrackID = ""
        if let item = json["item"] as? [String: Any] {
            newTrackID = item["id"] as? String ?? ""
            self.trackName = item["name"] as? String ?? "Unknown"
            if let artists = item["artists"] as? [[String: Any]], let firstArtist = artists.first {
                self.artistName = firstArtist["name"] as? String ?? "Unknown"
            }
            if let album = item["album"] as? [String: Any], let images = album["images"] as? [[String: Any]], let firstImage = images.first {
                self.albumArtURL = firstImage["url"] as? String ?? ""
            }
            self.duration = (item["duration_ms"] as? Double ?? 0) / 1000.0
        }
        
        self.progress = (json["progress_ms"] as? Double ?? 0) / 1000.0
        self.isPlaying = json["is_playing"] as? Bool ?? false
        self.isShuffled = json["shuffle_state"] as? Bool ?? false
        self.repeatMode = json["repeat_state"] as? String ?? "off"

        if let device = json["device"] as? [String: Any] {
            self.volume = device["volume_percent"] as? Int ?? 50
            self.deviceName = device["name"] as? String ?? ""
        } else {
            // Fallback to system volume if device info is missing
            self.updateSystemVolume()
        }

        // Fetch lyrics if the track has changed
        if newTrackID != self.currentTrackID && !newTrackID.isEmpty {
            self.currentTrackID = newTrackID
            Task {
                await fetchLyrics(artist: self.artistName, track: self.trackName)
            }
        }
    }

    private func fetchLyrics(artist: String, track: String) async {
        guard let url = URL(string: "https://lrclib.net/api/get?artist_name=\(artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&track_name=\(track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                if let syncedLrc = json?["syncedLyrics"] as? String {
                    self.syncedLyrics = parseLRC(syncedLrc)
                } else {
                    self.syncedLyrics = []
                }

                self.lyrics = json?["plainLyrics"] as? String ?? ""
            } else {
                self.lyrics = ""
                self.syncedLyrics = []
            }
        } catch {
            self.lyrics = ""
            self.syncedLyrics = []
        }
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d+):(\\d+\\.\\d+)\\](.*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        let nsLrc = lrc as NSString
        let matches = regex?.matches(in: lrc, options: [], range: NSRange(location: 0, length: nsLrc.length)) ?? []
        
        for match in matches {
            let minutes = Double(nsLrc.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(nsLrc.substring(with: match.range(at: 2))) ?? 0
            let text = nsLrc.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            
            let timestamp = (minutes * 60) + seconds
            lines.append(LyricLine(timestamp: timestamp, text: text))
        }
        
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private func refreshAccessToken() async {
        guard let refresh = refreshToken else { return }
        
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        let authString = "\(clientID):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authString)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "grant_type=refresh_token&refresh_token=\(refresh)"
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newToken = json["access_token"] as? String {
                self.accessToken = newToken
            }
        } catch {
            self.error = "Token Refresh Failed: \(error.localizedDescription)"
        }
    }

    func togglePlay() async {
        if useSystemNowPlaying {
            let script = "tell application \"Spotify\" to playpause"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
            await fetchPlayerDataFromSystem()
            return
        }
        
        guard let token = accessToken else { return }
        let url = isPlaying ? "https://api.spotify.com/v1/me/player/pause" : "https://api.spotify.com/v1/me/player/play"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func nextTrack() async {
        if useSystemNowPlaying {
            let script = "tell application \"Spotify\" to next track"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
            await fetchPlayerDataFromSystem()
            return
        }
        
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/next")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func previousTrack() async {
        if useSystemNowPlaying {
            let script = "tell application \"Spotify\" to previous track"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
            await fetchPlayerDataFromSystem()
            return
        }
        
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/previous")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func setVolume(_ volume: Int) async {
        if useSystemNowPlaying {
            let script = "tell application \"Spotify\" to set sound volume to \(volume)"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
            self.volume = volume
            return
        }
        
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/volume?volume_percent=\(volume)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        self.volume = volume
    }

    func toggleShuffle() async {
        guard let token = accessToken else { return }
        let newState = !isShuffled
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/shuffle?state=\(newState)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        self.isShuffled = newState
    }

    func cycleRepeat() async {
        guard let token = accessToken else { return }
        let nextMode: String
        switch repeatMode {
        case "off": nextMode = "context"
        case "context": nextMode = "track"
        default: nextMode = "off"
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/repeat?state=\(nextMode)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        self.repeatMode = nextMode
    }

    func fetchRecentlyPlayed() async {
        guard isAuthenticated else { return }
        if accessToken == nil { await refreshAccessToken() }
        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=5")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                self.recommendations = items.compactMap { item -> SpotifyTrack? in
                    guard let track = item["track"] as? [String: Any],
                          let id = track["id"] as? String,
                          let name = track["name"] as? String,
                          let artists = track["artists"] as? [[String: Any]],
                          let artistName = artists.first?["name"] as? String,
                          let album = track["album"] as? [String: Any],
                          let images = album["images"] as? [[String: Any]],
                          let imageUrl = images.first?["url"] as? String else {
                        return nil
                    }
                    return SpotifyTrack(id: id, name: name, artistName: artistName, albumArtURL: imageUrl)
                }
            }
        } catch {
            print("Failed to fetch recently played: \(error.localizedDescription)")
        }
    }

    func fetchQueue() async {
        guard isAuthenticated else { return }
        if accessToken == nil { await refreshAccessToken() }
        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["queue"] as? [[String: Any]] {
                self.queue = items.prefix(10).compactMap { track -> SpotifyTrack? in
                    guard let id = track["id"] as? String,
                          let name = track["name"] as? String,
                          let artists = track["artists"] as? [[String: Any]],
                          let artistName = artists.first?["name"] as? String,
                          let album = track["album"] as? [String: Any],
                          let images = album["images"] as? [[String: Any]],
                          let imageUrl = images.first?["url"] as? String else {
                        return nil
                    }
                    return SpotifyTrack(id: id, name: name, artistName: artistName, albumArtURL: imageUrl)
                }
            }
        } catch {
            print("Failed to fetch queue: \(error.localizedDescription)")
        }
    }
}

private final class AuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationAnchor()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
