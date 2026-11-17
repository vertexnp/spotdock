import Foundation
import SwiftUI
import Combine
import AppKit
import CoreAudio
import AudioToolbox

enum MediaPlatform: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    case youtube = "YouTube"
    case soundcloud = "SoundCloud"
    case browser = "Web Media"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .spotify: return "music.note"
        case .appleMusic: return "apple.logo"
        case .youtube: return "play.rectangle.fill"
        case .soundcloud: return "waveform.circle.fill"
        case .browser: return "globe"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .spotify: return .green
        case .appleMusic: return Color(red: 0.98, green: 0.22, blue: 0.35)
        case .youtube: return Color(red: 1.0, green: 0.15, blue: 0.15)
        case .soundcloud: return Color(red: 1.0, green: 0.45, blue: 0.0)
        case .browser: return .blue
        }
    }
}

enum AudioHelper {
    /// Fetches system master volume efficiently via CoreAudio (0% CPU, no AppleScript)
    static func getSystemVolume() -> Int {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        guard status == noErr else { return 50 }

        var volume: Float32 = 0.0
        propertySize = UInt32(MemoryLayout<Float32>.size)
        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let volStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &volume
        )
        
        if volStatus == noErr {
            return Int(round(volume * 100.0))
        }
        return 50
    }
}

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
    @Published var mediaPlatform: MediaPlatform = .youtube

    private var timer: AnyCancellable?
    private var currentMediaURL: String = ""
    
    private init() {
        startPolling()
    }
    
    func startPolling() {
        // Polling interval 2.5s is lightweight and fast enough for background tracking
        timer = Timer.publish(every: 2.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateSystemVolume()
                Task.detached(priority: .utility) {
                    await self.checkFallbackSources()
                }
            }
    }

    private func updateSystemVolume() {
        let vol = AudioHelper.getSystemVolume()
        if self.systemVolume != vol {
            self.systemVolume = vol
        }
    }

    private func checkFallbackSources() async {
        // Fast bail-out: If Spotify is playing, or universal playback is disabled, do nothing
        let (shouldCheck, spotifyPlaying) = await MainActor.run {
            let player = SpotifyPlayer.shared
            return (player.useUniversalNowPlaying && !player.isPlaying, player.isPlaying)
        }
        
        guard shouldCheck else {
            if spotifyPlaying {
                await MainActor.run {
                    if !self.trackName.isEmpty {
                        self.trackName = ""
                        self.artistName = ""
                        self.isPlaying = false
                        self.albumArt = nil
                        self.currentMediaURL = ""
                        self.mediaPlatform = .spotify
                    }
                }
            }
            return
        }

        // 1. Check Apple Music (native macOS Music.app)
        if await checkAppleMusic() {
            return
        }

        // 2. Check Browser Fallbacks (YouTube & SoundCloud)
        await checkBrowserMedia()
    }

    private func checkAppleMusic() async -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return false
        }

        let scriptSource = """
        try
            tell application "Music"
                set pState to (player state as string)
                if pState is "playing" or pState is "paused" then
                    set tName to (name of current track)
                    set tArtist to (artist of current track)
                    set tPos to (player position as string)
                    set tDur to (duration of current track as string)
                    return tName & "|" & tArtist & "|" & pState & "|" & tPos & "|" & tDur
                end if
            end tell
        end try
        return ""
        """

        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let output = script.executeAndReturnError(&error)
            if error == nil, let result = output.stringValue, !result.isEmpty, result.contains("|") {
                let parts = result.components(separatedBy: "|")
                if parts.count >= 5 {
                    let isPlaying = (parts[2] == "playing")
                    let prog = Double(parts[3]) ?? 0
                    let dur = Double(parts[4]) ?? 0

                    await MainActor.run {
                        self.bundleID = "com.apple.Music"
                        self.mediaPlatform = .appleMusic
                        self.trackName = parts[0]
                        self.artistName = parts[1]
                        self.isPlaying = isPlaying
                        self.progress = prog
                        self.duration = dur
                    }

                    // Fetch Apple Music Artwork if needed
                    await fetchAppleMusicArtwork()
                    return isPlaying
                }
            }
        }
        return false
    }

    private func fetchAppleMusicArtwork() async {
        let scriptSource = """
        try
            tell application "Music"
                if exists (artwork 1 of current track) then
                    return raw data of artwork 1 of current track
                end if
            end tell
        end try
        return ""
        """
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            let data = output.data
            if error == nil && !data.isEmpty, let image = NSImage(data: data) {
                await MainActor.run {
                    self.albumArt = image
                }
            }
        }
    }

    private func checkBrowserMedia() async {
        let browsers = [
            ("com.brave.Browser", "Brave Browser"),
            ("com.google.Chrome", "Google Chrome"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.apple.Safari", "Safari")
        ]
        
        var bestFoundTab: (platform: MediaPlatform, bundleID: String, title: String, artist: String, url: String, isPlaying: Bool, priority: Int, progress: Double, duration: Double, artURL: String)? = nil
        
        for browser in browsers {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.0).isEmpty else {
                continue
            }
            
            let scriptSource: String
            if browser.1 == "Safari" {
                scriptSource = """
                try
                    tell application id "com.apple.Safari"
                        repeat with w in windows
                            set mediaTabs to (tabs of w whose URL contains "youtube.com" or URL contains "youtu.be" or URL contains "soundcloud.com")
                            repeat with t in mediaTabs
                                set theURL to URL of t
                                if theURL contains "soundcloud.com" then
                                    try
                                        set jsResult to do JavaScript "(() => { const p = document.querySelector('.playControl'); const isPlaying = p ? p.classList.contains('playing') : false; const tEl = document.querySelector('.playbackSoundBadge__titleLink'); const aEl = document.querySelector('.playbackSoundBadge__lightLink'); const t = tEl ? (tEl.getAttribute('title') || tEl.innerText || '') : ''; const a = aEl ? (aEl.getAttribute('title') || aEl.innerText || '') : ''; const v = document.querySelector('audio'); const prog = v ? Math.floor(v.currentTime) : 0; const dur = v ? Math.floor(v.duration || 0) : 0; const img = document.querySelector('.playbackSoundBadge__avatar img'); const art = img ? img.src : ''; return isPlaying + '|' + t + '|' + a + '|' + prog + '|' + dur + '|' + art; })()" in t
                                        return "sc|" & theURL & "|" & jsResult
                                    on error
                                        return "sc|" & theURL & "|false|||0|0|"
                                    end try
                                else
                                    try
                                        set jsResult to do JavaScript "(() => { const v = document.querySelector('video') || document.querySelector('audio'); return v ? ((!v.paused && v.readyState >= 2) + '|' + Math.floor(v.currentTime) + '|' + Math.floor(v.duration || 0)) : 'false|0|0'; })()" in t
                                        return "yt|" & (name of t) & "|" & theURL & "|" & jsResult
                                    on error
                                        return "yt|" & (name of t) & "|" & theURL & "|false|0|0"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                end try
                return ""
                """
            } else if browser.1 == "Firefox" {
                scriptSource = """
                try
                    tell application id "org.mozilla.firefox"
                        repeat with w in windows
                            set wName to name of w
                            if wName contains "SoundCloud" then
                                return "sc|https://soundcloud.com|true|" & wName & "|SoundCloud|0|0|"
                            else if wName contains "YouTube" then
                                return "yt|" & wName & "|https://youtube.com|true|0|0"
                            end if
                        end repeat
                    end tell
                end try
                return ""
                """
            } else {
                // Chromium: Brave, Chrome, Arc, Edge
                scriptSource = """
                try
                    tell application id "\(browser.0)"
                        repeat with w in windows
                            set mediaTabs to (tabs of w whose URL contains "youtube.com" or URL contains "youtu.be" or URL contains "soundcloud.com")
                            repeat with t in mediaTabs
                                set theURL to URL of t
                                if theURL contains "soundcloud.com" then
                                    try
                                        tell t to set jsResult to execute javascript "(() => { const p = document.querySelector('.playControl'); const isPlaying = p ? p.classList.contains('playing') : false; const tEl = document.querySelector('.playbackSoundBadge__titleLink'); const aEl = document.querySelector('.playbackSoundBadge__lightLink'); const t = tEl ? (tEl.getAttribute('title') || tEl.innerText || '') : ''; const a = aEl ? (aEl.getAttribute('title') || aEl.innerText || '') : ''; const v = document.querySelector('audio'); const prog = v ? Math.floor(v.currentTime) : 0; const dur = v ? Math.floor(v.duration || 0) : 0; const img = document.querySelector('.playbackSoundBadge__avatar img'); const art = img ? img.src : ''; return isPlaying + '|' + t + '|' + a + '|' + prog + '|' + dur + '|' + art; })()"
                                        return "sc|" & theURL & "|" & jsResult
                                    on error
                                        return "sc|" & theURL & "|false|||0|0|"
                                    end try
                                else
                                    try
                                        tell t to set jsResult to execute javascript "(() => { const v = document.querySelector('video') || document.querySelector('audio'); return v ? ((!v.paused && v.readyState >= 2) + '|' + Math.floor(v.currentTime) + '|' + Math.floor(v.duration || 0)) : 'false|0|0'; })()"
                                        return "yt|" & (title of t) & "|" & theURL & "|" & jsResult
                                    on error
                                        return "yt|" & (title of t) & "|" & theURL & "|false|0|0"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                end try
                return ""
                """
            }
            
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let output = script.executeAndReturnError(&error)
                if error == nil, let result = output.stringValue, !result.isEmpty, result.contains("|") {
                    let parts = result.components(separatedBy: "|")
                    let prefix = parts[0]
                    
                    if prefix == "sc" && parts.count >= 8 {
                        // SoundCloud result: sc | url | isPlaying | title | artist | prog | dur | artURL
                        let url = parts[1]
                        let isPlaying = (parts[2] == "true")
                        let title = parts[3].isEmpty ? "SoundCloud Track" : parts[3]
                        let artist = parts[4].isEmpty ? "SoundCloud" : parts[4]
                        let prog = Double(parts[5]) ?? 0
                        let dur = Double(parts[6]) ?? 0
                        let artURL = parts.count >= 8 ? parts[7] : ""
                        let priority = isPlaying ? 2 : 1
                        
                        if bestFoundTab == nil || priority > bestFoundTab!.priority {
                            bestFoundTab = (.soundcloud, browser.0, title, artist, url, isPlaying, priority, prog, dur, artURL)
                        }
                        if isPlaying { break }
                    } else if prefix == "yt" && parts.count >= 5 {
                        // YouTube result: yt | title | url | isPlaying | prog | dur
                        let title = parts[1]
                        let url = parts[2]
                        let isPlaying = (parts[3] == "true")
                        let prog = parts.count >= 5 ? (Double(parts[4]) ?? 0) : 0
                        let dur = parts.count >= 6 ? (Double(parts[5]) ?? 0) : 0
                        let priority = isPlaying ? 2 : 1
                        
                        if bestFoundTab == nil || priority > bestFoundTab!.priority {
                            bestFoundTab = (.youtube, browser.0, title, "", url, isPlaying, priority, prog, dur, "")
                        }
                        if isPlaying { break }
                    }
                }
            }
        }
        
        if let best = bestFoundTab {
            await MainActor.run {
                self.bundleID = best.bundleID
                self.mediaPlatform = best.platform
                self.isPlaying = best.isPlaying
                self.progress = best.progress
                self.duration = best.duration
                
                if best.platform == .soundcloud {
                    self.trackName = best.title
                    self.artistName = best.artist
                    if self.currentMediaURL != best.url {
                        self.currentMediaURL = best.url
                        if !best.artURL.isEmpty {
                            self.fetchImageURL(url: best.artURL)
                        } else {
                            self.albumArt = nil
                        }
                    }
                } else {
                    // YouTube
                    var finalTitle = best.title
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
                    
                    if self.currentMediaURL != best.url {
                        self.currentMediaURL = best.url
                        self.fetchYouTubeThumbnail(url: best.url)
                    }
                }
            }
        } else {
            await MainActor.run {
                self.trackName = ""
                self.artistName = ""
                self.isPlaying = false
                self.progress = 0
                self.duration = 0
                self.albumArt = nil
                self.currentMediaURL = ""
            }
        }
    }

    private func fetchImageURL(url: String) {
        guard let imageURL = URL(string: url) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: imageURL),
               let image = NSImage(data: data) {
                await MainActor.run {
                    self.albumArt = image
                }
            }
        }
    }

    private func fetchYouTubeThumbnail(url: String) {
        guard let videoID = extractYoutubeID(from: url) else { return }
        let thumbURL = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
        fetchImageURL(url: thumbURL)
    }

    private func extractYoutubeID(from url: String) -> String? {
        let pattern = #"(?<=v=)[^&]+"#
        if let range = url.range(of: pattern, options: .regularExpression) {
            return String(url[range])
        }
        return nil
    }

    func togglePlay() {
        Task.detached(priority: .userInitiated) {
            let platform = await MainActor.run { self.mediaPlatform }
            
            if platform == .appleMusic {
                let script = "try\ntell application \"Music\" to playpause\nend try"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
                await MainActor.run { self.isPlaying.toggle() }
                return
            }
            
            await MainActor.run { self.isPlaying.toggle() }
            
            if platform == .soundcloud {
                let js = """
                (() => {
                    const btn = document.querySelector('.playControl');
                    if (btn) { btn.click(); return 'clicked'; }
                    const a = document.querySelector('audio');
                    if (a) {
                        if (a.paused) a.play(); else a.pause();
                        return 'toggled';
                    }
                    return 'not found';
                })()
                """
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "soundcloud.com")
            } else {
                let js = """
                (() => {
                    const p = document.getElementById('movie_player') || document.querySelector('ytmusic-player');
                    if (p && typeof p.getPlayerState === 'function') {
                        if (p.getPlayerState() === 1) { p.pauseVideo(); return 'paused'; }
                        else { p.playVideo(); return 'playing'; }
                    }
                    const v = document.querySelector('video') || document.querySelector('audio');
                    if (v) {
                        if (v.paused) { v.play(); return 'playing'; }
                        else { v.pause(); return 'paused'; }
                    }
                    const btn = document.querySelector('.ytp-play-button') || document.querySelector('#play-pause-button');
                    if (btn) { btn.click(); return 'clicked'; }
                    return 'not found';
                })()
                """
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "youtube.com")
            }
        }
    }

    func nextTrack() {
        Task.detached(priority: .userInitiated) {
            let platform = await MainActor.run { self.mediaPlatform }
            
            if platform == .appleMusic {
                let script = "try\ntell application \"Music\" to next track\nend try"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
                try? await Task.sleep(nanoseconds: 700_000_000)
                _ = await self.checkAppleMusic()
                return
            }
            
            if platform == .soundcloud {
                let js = "(() => { const b = document.querySelector('.skipControl__next') || document.querySelector('.playControls__next'); if (b) b.click(); })()"
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "soundcloud.com")
            } else {
                let js = """
                (() => {
                    const p = document.getElementById('movie_player') || document.querySelector('ytmusic-player');
                    if (p && typeof p.nextVideo === 'function') {
                        p.nextVideo();
                        return 'next';
                    }
                    const btn = document.querySelector('.ytp-next-button') || document.querySelector('.next-button') || document.querySelector('a.ytp-next-button');
                    if (btn) { btn.click(); return 'clicked'; }
                    return 'not found';
                })()
                """
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "youtube.com")
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.checkBrowserMedia()
        }
    }

    func previousTrack() {
        Task.detached(priority: .userInitiated) {
            let platform = await MainActor.run { self.mediaPlatform }
            
            if platform == .appleMusic {
                let script = "try\ntell application \"Music\" to previous track\nend try"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
                try? await Task.sleep(nanoseconds: 700_000_000)
                _ = await self.checkAppleMusic()
                return
            }
            
            if platform == .soundcloud {
                let js = "(() => { const b = document.querySelector('.skipControl__previous') || document.querySelector('.playControls__prev'); if (b) b.click(); const a = document.querySelector('audio'); if (a) a.currentTime = 0; })()"
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "soundcloud.com")
            } else {
                let js = """
                (() => {
                    const p = document.getElementById('movie_player') || document.querySelector('ytmusic-player');
                    if (p && typeof p.previousVideo === 'function') {
                        p.previousVideo();
                        return 'prev';
                    }
                    const btn = document.querySelector('.ytp-prev-button') || document.querySelector('.previous-button');
                    if (btn) { btn.click(); return 'clicked'; }
                    const v = document.querySelector('video');
                    if (v) { v.currentTime = 0; return 'restart'; }
                    return 'not found';
                })()
                """
                await self.executeJavaScriptInBrowserTab(js: js, matchDomain: "youtube.com")
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.checkBrowserMedia()
        }
    }

    func seek(to seconds: Double) {
        Task.detached(priority: .userInitiated) {
            let platform = await MainActor.run { self.mediaPlatform }
            
            if platform == .appleMusic {
                let script = "try\ntell application \"Music\" to set player position to \(seconds)\nend try"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
                await MainActor.run { self.progress = seconds }
                return
            }
            
            let js = "(() => { const v = document.querySelector('video') || document.querySelector('audio'); if (v) v.currentTime = \(seconds); })()"
            let domain = platform == .soundcloud ? "soundcloud.com" : "youtube.com"
            await self.executeJavaScriptInBrowserTab(js: js, matchDomain: domain)
            await MainActor.run {
                self.progress = seconds
            }
        }
    }

    private func executeJavaScriptInBrowserTab(js: String, matchDomain: String) async {
        let currentBundleID = await MainActor.run { self.bundleID }
        
        let browsers = [
            ("com.brave.Browser", "Brave Browser"),
            ("com.google.Chrome", "Google Chrome"),
            ("com.apple.Safari", "Safari")
        ]
        
        let targetBrowsers: [(String, String)]
        if !currentBundleID.isEmpty, let matched = browsers.first(where: { $0.0 == currentBundleID }) {
            targetBrowsers = [matched]
        } else {
            targetBrowsers = browsers
        }
        
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        
        for browser in targetBrowsers {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.0).isEmpty else { continue }
            
            let scriptSource: String
            if browser.0 == "com.apple.Safari" {
                scriptSource = """
                try
                    tell application id "com.apple.Safari"
                        repeat with w in windows
                            set targetTabs to (tabs of w whose URL contains "\(matchDomain)")
                            repeat with t in targetTabs
                                do JavaScript "\(escapedJS)" in t
                                return "success"
                            end repeat
                        end repeat
                    end tell
                end try
                return ""
                """
            } else {
                scriptSource = """
                try
                    tell application id "\(browser.0)"
                        repeat with w in windows
                            set targetTabs to (tabs of w whose URL contains "\(matchDomain)")
                            repeat with t in targetTabs
                                tell t to execute javascript "\(escapedJS)"
                                return "success"
                            end repeat
                        end repeat
                    end tell
                end try
                return ""
                """
            }
            
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                let res = script.executeAndReturnError(&error)
                if error == nil && res.stringValue == "success" {
                    break
                }
            }
        }
    }
}
