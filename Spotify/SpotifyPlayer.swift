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

    private var currentTrackID: String = ""
    private var pollingTimer: AnyCancellable?
    private let clientID = EnvironmentManager.shared.get("SPOTIFY_CLIENT_ID") ?? ""
    private let clientSecret = EnvironmentManager.shared.get("SPOTIFY_CLIENT_SECRET") ?? ""
    private var accessToken: String? = nil
    private var refreshToken: String?

    private init() {
        if let savedToken = UserDefaults.standard.string(forKey: "SpotifyRefreshToken") {
            self.refreshToken = savedToken
            self.isAuthenticated = true
        } else if let envToken = EnvironmentManager.shared.get("SPOTIFY_REFRESH_TOKEN"), !envToken.isEmpty {
            self.refreshToken = envToken
            self.isAuthenticated = true
        }
    }

    func startPolling() {
        pollingTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    guard let self = self else { return }
                    // Always try API unless rate limited. The rate limiting logic is handled in refreshPlayerData.
                    await self.refreshPlayerData()
                }
            }
    }

    func login() {
        let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"
        let redirectURI = "playerwidget://callback"
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        
        guard let authURL = components.url else { return }
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "spotifywidget") { callbackURL, error in
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
                await refreshPlayerData()
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
        guard isAuthenticated else { return }

        if accessToken == nil {
            await refreshAccessToken()
        }

        guard let token = accessToken else { return }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            print("🌐 [API] Fetching player data...")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 [API] Response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // Clear any previous errors on successful response
                    self.error = nil
                    self.isRateLimited = false
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let track = json?["item"] as? [String: Any], let name = track["name"] as? String {
                        print("🌐 [API] Now playing: \(name)")
                    }
                    updatePlaybackState(json)
                } else if httpResponse.statusCode == 204 {
                    // Clear any previous errors on successful response
                    self.error = nil
                    self.isRateLimited = false
                    print("🌐 [API] Nothing playing")
                    self.trackName = "Nothing Playing"
                    self.artistName = ""
                    self.albumArtURL = ""
                    self.isPlaying = false
                    self.currentTrackID = ""
                    self.syncedLyrics = []
                    self.lyrics = ""
                } else if httpResponse.statusCode == 429 {
                    // Rate limit exceeded - show specific error
                    print("🌐 [API] ⚠️ Rate limit reached (429)")
                    self.isRateLimited = true
                    self.error = "[Sorry you will have to wait ...]"
                } else if httpResponse.statusCode == 401 {
                    print("🌐 [API] Unauthorized (401) - refreshing token")
                    await refreshAccessToken()
                }
            }
        } catch {
            print("🌐 [API] Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
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
        guard let token = accessToken else { return }
        let url = isPlaying ? "https://api.spotify.com/v1/me/player/pause" : "https://api.spotify.com/v1/me/player/play"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func nextTrack() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/next")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func previousTrack() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/previous")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        await refreshPlayerData()
    }

    func setVolume(_ volume: Int) async {
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
}

private final class AuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationAnchor()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
