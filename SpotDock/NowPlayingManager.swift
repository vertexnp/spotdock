import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()
    
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var bundleID: String = ""
    @Published var systemVolume: Int = 50

    private var timer: AnyCancellable?
    private var currentYouTubeURL: String = ""
    
    private init() {
        startPolling()
    }
    
    func startPolling() {
        // Reduced frequency from 1s to 3s (AppleScript is expensive)
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    // Only check browser if Spotify isn't already handled by SpotifyPlayer
                    if !SpotifyPlayer.shared.isPlaying {
                        self?.checkBrowserFallback()
                    }
                    self?.updateSystemVolume()
                }
            }
    }

    private func updateSystemVolume() {
        let scriptSource = "output volume of (get volume settings)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                let vol = Int(result.int32Value)
                if self.systemVolume != vol {
                    self.systemVolume = vol
                }
            }
        }
    }

    private func checkBrowserFallback() {
        // Skip browser check if Spotify is playing (priority logic will handle this in View, but saving resources here)
        // We scan all supported browsers for active YouTube tabs
        let browsers = [
            ("com.brave.Browser", "Brave Browser"),
            ("com.google.Chrome", "Google Chrome"),
            ("com.apple.Safari", "Safari")
        ]
        
        for browser in browsers {
            let scriptSource = browser.1 == "Safari" ? """
            tell application "Safari"
                if it is running then
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "youtube.com/watch" then
                                return (name of t) & "|" & (URL of t)
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            """ : """
            tell application "\(browser.1)"
                if it is running then
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "youtube.com/watch" then
                                return (title of t) & "|" & (URL of t)
                            end if
                        end repeat
                    end repeat
                end if
            end tell
            """
            
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                if let result = script.executeAndReturnError(&error).stringValue, result.contains("|") {
                    let parts = result.components(separatedBy: "|")
                    let title = parts[0]
                    let url = parts[1]
                    
                    DispatchQueue.main.async {
                        self.bundleID = browser.0
                        var finalTitle = title
                        if title.hasSuffix(" - YouTube") { finalTitle = String(title.dropLast(10)) }
                        
                        let titleParts = finalTitle.components(separatedBy: " - ")
                        if titleParts.count >= 2 {
                            self.trackName = titleParts[1]
                            self.artistName = titleParts[0]
                        } else {
                            self.trackName = finalTitle
                            self.artistName = "YouTube"
                        }
                        
                        self.isPlaying = true // If tab exists, we assume it's the active media
                        if self.currentYouTubeURL != url {
                            self.currentYouTubeURL = url
                            self.fetchYouTubeThumbnail(url: url)
                        }
                    }
                    return 
                }
            }
        }
        
        // If no YouTube tab found in any browser
        DispatchQueue.main.async {
            self.trackName = ""
            self.artistName = ""
            self.isPlaying = false
            self.albumArt = nil
            self.currentYouTubeURL = ""
        }
    }

    private func fetchYouTubeThumbnail(url: String) {
        guard let videoID = extractYoutubeID(from: url) else { return }
        let thumbURL = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        
        Task {
            if let url = URL(string: thumbURL), let (data, _) = try? await URLSession.shared.data(from: url) {
                if let image = NSImage(data: data) {
                    await MainActor.run {
                        self.albumArt = image
                    }
                }
            }
        }
    }

    private func extractYoutubeID(from url: String) -> String? {
        let pattern = #"(?<=v=)[^&]+"#
        if let range = url.range(of: pattern, options: .regularExpression) {
            return String(url[range])
        }
        return nil
    }

    // Playback controls for browsers via AppleScript
    func togglePlay() {
        executeBrowserCommand("if (player.getPlayerState() == 1) { player.pauseVideo(); } else { player.playVideo(); }")
    }

    func nextTrack() {
        executeBrowserCommand("window.history.forward()") // Basic fallback
    }

    func previousTrack() {
        executeBrowserCommand("window.history.back()") // Basic fallback
    }

    private func executeBrowserCommand(_ js: String) {
        // This is complex for general browsers, keeping it simple or skipping for now
        // Most users prefer system keys anyway
    }
}
