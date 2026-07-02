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
        // Frequency of 0.8s for responsive visualizer bars
        timer = Timer.publish(every: 0.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Run AppleScript on a background thread to prevent UI freezing
                Task.detached(priority: .userInitiated) {
                    await self?.checkBrowserFallback()
                    await self?.updateSystemVolume()
                }
            }
    }

    private func updateSystemVolume() async {
        let scriptSource = "output volume of (get volume settings)"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                let vol = Int(result.int32Value)
                await MainActor.run {
                    if self.systemVolume != vol {
                        self.systemVolume = vol
                    }
                }
            }
        }
    }

    private func checkBrowserFallback() async {
        let browsers = [
            ("com.brave.Browser", "Brave Browser"),
            ("com.google.Chrome", "Google Chrome"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.apple.Safari", "Safari")
        ]
        
        var bestFoundTab: (bundleID: String, title: String, url: String, isPlaying: Bool, priority: Int)? = nil
        
        for browser in browsers {
            let scriptSource: String
            if browser.1 == "Safari" {
                scriptSource = """
                try
                    if application id "com.apple.Safari" is running then
                        tell application id "com.apple.Safari"
                            set backupInfo to ""
                            try
                                repeat with w in windows
                                    repeat with t in tabs of w
                                        try
                                            set theURL to URL of t
                                            if theURL contains "youtube.com" or theURL contains "youtu.be" then
                                                set currentInfo to (name of t) & "|" & (URL of t)
                                                set isPlaying to false
                                                try
                                                    set jsResult to do JavaScript "Array.from(document.querySelectorAll('video, audio')).some(el => !el.paused && el.readyState >= 2)" in t
                                                    if jsResult is true or jsResult is "true" or jsResult is 1 then
                                                        set isPlaying to true
                                                    end if
                                                on error
                                                    -- JS access not allowed or fails.
                                                end try
                                                
                                                if isPlaying then
                                                    return currentInfo & "|true"
                                                end if
                                                if backupInfo is "" then set backupInfo to currentInfo & "|false"
                                            end if
                                        end try
                                    end repeat
                                end repeat
                            end try
                            return backupInfo
                        end tell
                    end if
                end try
                return ""
                """
            } else if browser.1 == "Firefox" {
                scriptSource = """
                try
                    if application id "org.mozilla.firefox" is running then
                        tell application id "org.mozilla.firefox"
                            try
                                repeat with w in windows
                                    set wName to name of w
                                    if wName contains "YouTube" then
                                        return wName & "|https://youtube.com|true"
                                    end if
                                end repeat
                            end try
                        end tell
                    end if
                end try
                return ""
                """
            } else {
                scriptSource = """
                try
                    if application id "\(browser.0)" is running then
                        tell application id "\(browser.0)"
                            set backupInfo to ""
                            try
                                repeat with w in windows
                                    repeat with t in tabs of w
                                        try
                                            set theURL to URL of t
                                            if theURL contains "youtube.com" or theURL contains "youtu.be" then
                                                set currentInfo to (title of t) & "|" & theURL
                                                set isPlaying to false
                                                try
                                                    tell t to set jsResult to execute javascript "Array.from(document.querySelectorAll('video, audio')).some(el => !el.paused && el.readyState >= 2)"
                                                    if jsResult is true or jsResult is "true" or jsResult is 1 then
                                                        set isPlaying to true
                                                    end if
                                                on error
                                                    -- JS access not allowed or fails. Fallback to active tab check and checking if window title has speaker icon.
                                                    try
                                                        if (id of t) is (id of active tab of w) then
                                                            set wName to name of w
                                                            if wName contains "🔊" or wName contains "Audio" then
                                                                set isPlaying to true
                                                            end if
                                                        end if
                                                    end try
                                                end try
                                                
                                                if isPlaying then
                                                    return currentInfo & "|true"
                                                end if
                                                if backupInfo is "" then set backupInfo to currentInfo & "|false"
                                            end if
                                        end try
                                    end repeat
                                end repeat
                            end try
                            return backupInfo
                        end tell
                    end if
                end try
                return ""
                """
            }
            
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let output = script.executeAndReturnError(&error)
                if error == nil, let result = output.stringValue, result != "", result.contains("|") {
                    let parts = result.components(separatedBy: "|")
                    if parts.count >= 3 {
                        let isPlaying = (parts[2] == "true")
                        let priority = isPlaying ? 2 : 1
                        
                        if bestFoundTab == nil || priority > bestFoundTab!.priority {
                            bestFoundTab = (browser.0, parts[0], parts[1], isPlaying, priority)
                        }
                        if isPlaying { break }
                    }
                }
            }
        }
        
        if let best = bestFoundTab {
            await MainActor.run {
                self.bundleID = best.bundleID
                var finalTitle = best.title
                
                // Clean YouTube title
                if finalTitle.hasSuffix(" - YouTube") { finalTitle = String(finalTitle.dropLast(10)) }
                if finalTitle.hasSuffix(" - YouTube Music") { finalTitle = String(finalTitle.dropLast(16)) }
                if finalTitle.hasPrefix("(") && finalTitle.contains(") ") {
                    if let range = finalTitle.range(of: ") ") {
                        finalTitle = String(finalTitle[range.upperBound...])
                    }
                }
                
                let titleParts = finalTitle.components(separatedBy: " - ")
                if titleParts.count >= 2 {
                    self.trackName = titleParts[1]
                    self.artistName = titleParts[0]
                } else {
                    self.trackName = finalTitle
                    self.artistName = best.url.contains("music.youtube.com") ? "YouTube Music" : "YouTube"
                }
                
                self.isPlaying = best.isPlaying
                
                if self.currentYouTubeURL != best.url {
                    self.currentYouTubeURL = best.url
                    self.fetchYouTubeThumbnail(url: best.url)
                }
            }
        } else {
            await MainActor.run {
                self.trackName = ""
                self.artistName = ""
                self.isPlaying = false
                self.albumArt = nil
                self.currentYouTubeURL = ""
            }
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

    func togglePlay() {}
    func nextTrack() {}
    func previousTrack() {}
}
