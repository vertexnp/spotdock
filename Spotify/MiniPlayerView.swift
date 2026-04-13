//
//  MiniPlayerView.swift
//  Spotify
//

import SwiftUI

enum ViewMode {
    case player
    case lyrics
}

struct MiniPlayerView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @State private var viewMode: ViewMode = .player
    @State private var localVolume: Double = 50
    
    @AppStorage("miniPlayerLook") private var miniPlayerLook = "Default"
    @AppStorage("miniPlayerCompactMode") private var miniPlayerCompactMode = false
    
    // macOS 15 Widget Style Corner Radius
    private let widgetCornerRadius: CGFloat = 34
    
    var body: some View {
        ZStack {
            if miniPlayerLook == "Retro Radio" {
                retroRadioBackground
            } else {
                defaultBackground
            }

            // Content
            Group {
                if viewMode == .player {
                    playerModeView
                } else {
                    lyricsModeView
                }
            }
            .padding(miniPlayerLook == "Retro Radio" ? 40 : (miniPlayerCompactMode ? 25 : 35))
        }
        .frame(width: 440, height: viewMode == .player ? (miniPlayerCompactMode ? 180 : 250) : 450)
        .onAppear {
            localVolume = Double(player.volume)
        }
        .onChange(of: player.volume) { oldValue, newValue in
            localVolume = Double(newValue)
        }
    }
    
    private var defaultBackground: some View {
        RoundedRectangle(cornerRadius: widgetCornerRadius, style: .continuous)
            .fill(Color(white: 0.15))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(20)
    }
    
    private var retroRadioBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.2, blue: 0.1), Color(red: 0.25, green: 0.1, blue: 0.05)], startPoint: .top, endPoint: .bottom))
                .padding(10)
            
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.15))
                .overlay(
                    Image(systemName: "circle.grid.3x3.fill")
                        .resizable(resizingMode: .tile)
                        .opacity(0.05)
                        .scaleEffect(0.5)
                )
                .padding(25)
        }
        .padding(10)
    }
    
    // MARK: - Player Mode
    private var playerModeView: some View {
        HStack(spacing: miniPlayerCompactMode ? 15 : 25) {
            // Album Art
            albumArt(size: miniPlayerCompactMode ? 100 : 140)
            
            VStack(alignment: .leading, spacing: 0) {
                // Top row with expand icon
                HStack {
                    Spacer()
                    expandButton
                }
                
                if !miniPlayerCompactMode { Spacer() }
                
                // Track Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.trackName)
                        .font(miniPlayerLook == "Retro Radio" ? .custom("AmericanTypewriter-Bold", size: miniPlayerCompactMode ? 16 : 20) : .system(size: miniPlayerCompactMode ? 16 : 20, weight: .bold))
                        .foregroundColor(miniPlayerLook == "Retro Radio" ? Color(red: 0.95, green: 0.9, blue: 0.7) : .white)
                        .lineLimit(1)
                    
                    Text(player.artistName)
                        .font(miniPlayerLook == "Retro Radio" ? .custom("AmericanTypewriter", size: miniPlayerCompactMode ? 12 : 15) : .system(size: miniPlayerCompactMode ? 12 : 15, weight: .medium))
                        .foregroundColor(miniPlayerLook == "Retro Radio" ? Color(red: 0.95, green: 0.9, blue: 0.7).opacity(0.7) : .white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.top, miniPlayerCompactMode ? 5 : 0)
                
                Spacer()
                
                // Controls
                HStack(spacing: miniPlayerCompactMode ? 15 : 25) {
                    Button(action: { Task { await player.previousTrack() } }) {
                        Image(systemName: "backward.fill").font(.system(size: miniPlayerCompactMode ? 14 : 18))
                    }.buttonStyle(WidgetButtonStyle(isRetro: miniPlayerLook == "Retro Radio"))
                    
                    Button(action: { Task { await player.togglePlay() } }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: miniPlayerCompactMode ? 18 : 24))
                            .foregroundColor(miniPlayerLook == "Retro Radio" ? Color(red: 0.1, green: 0.1, blue: 0.1) : .black)
                            .frame(width: miniPlayerCompactMode ? 36 : 50, height: miniPlayerCompactMode ? 36 : 50)
                            .background(miniPlayerLook == "Retro Radio" ? Color(red: 0.95, green: 0.9, blue: 0.7) : .white)
                            .clipShape(Circle())
                    }.buttonStyle(.plain)
                    
                    Button(action: { Task { await player.nextTrack() } }) {
                        Image(systemName: "forward.fill").font(.system(size: miniPlayerCompactMode ? 14 : 18))
                    }.buttonStyle(WidgetButtonStyle(isRetro: miniPlayerLook == "Retro Radio"))
                }
                
                if !miniPlayerCompactMode { Spacer() }
            }
        }
    }
    
    // MARK: - Lyrics Mode
    private var lyricsModeView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 15) {
                albumArt(size: miniPlayerCompactMode ? 60 : 80)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.trackName)
                        .font(.system(size: miniPlayerCompactMode ? 14 : 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(player.artistName)
                        .font(.system(size: miniPlayerCompactMode ? 11 : 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                    
                    HStack(spacing: 15) {
                        Button(action: { Task { await player.previousTrack() } }) {
                            Image(systemName: "backward.fill").font(.system(size: 12))
                        }.buttonStyle(WidgetButtonStyle(isRetro: miniPlayerLook == "Retro Radio"))
                        
                        Button(action: { Task { await player.togglePlay() } }) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .frame(width: 28, height: 28)
                                .background(Color.white)
                                .clipShape(Circle())
                        }.buttonStyle(.plain)
                        
                        Button(action: { Task { await player.nextTrack() } }) {
                            Image(systemName: "forward.fill").font(.system(size: 12))
                        }.buttonStyle(WidgetButtonStyle(isRetro: miniPlayerLook == "Retro Radio"))
                    }
                    .padding(.top, 5)
                }
                
                Spacer()
                expandButton
                    .padding(.top, 2) // Align with top of album art
            }
            
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if !player.syncedLyrics.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(player.syncedLyrics) { line in
                                Text(line.text)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(isCurrentLine(line) ? .white : .white.opacity(0.3))
                                    .scaleEffect(isCurrentLine(line) ? 1.02 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrentLine(line))
                                    .id(line.id)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 10) // Extra padding to prevent letter clipping
                            }
                        }
                        .padding(.top, 0)
                        .padding(.bottom, 200) // Allow bottom lines to scroll to center
                        .onChange(of: player.progress) { _, newValue in
                            if let currentLine = player.syncedLyrics.last(where: { $0.timestamp <= newValue }) {
                                withAnimation(.smooth) {
                                    proxy.scrollTo(currentLine.id, anchor: .center)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .center) {
                            Spacer()
                            Text("Lyrics for this music is not found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                            Spacer()
                        }
                        .frame(height: 200)
                    }
                }
            }
        }
    }
    
    private func albumArt(size: CGFloat) -> some View {
        ZStack {
            if !player.albumArtURL.isEmpty {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .cornerRadius(miniPlayerLook == "Retro Radio" ? 8 : (miniPlayerCompactMode ? 16 : 24))
                } placeholder: {
                    placeholderArt(size: size * 0.3)
                }
            } else {
                placeholderArt(size: size * 0.3)
            }
        }
        .frame(width: size, height: size)
    }
    
    private var expandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewMode = (viewMode == .player) ? .lyrics : .player
            }
        }) {
            Image(systemName: viewMode == .player ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .padding(8)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
    
    private func placeholderArt(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: miniPlayerLook == "Retro Radio" ? 8 : (miniPlayerCompactMode ? 16 : 24))
            .fill(Color.white.opacity(0.05))
            .overlay(Image(systemName: "music.note").font(.system(size: size)).foregroundColor(.white.opacity(0.1)))
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func isCurrentLine(_ line: LyricLine) -> Bool {
        guard let currentIndex = player.syncedLyrics.firstIndex(where: { $0.id == line.id }) else { return false }
        let nextLine = currentIndex + 1 < player.syncedLyrics.count ? player.syncedLyrics[currentIndex + 1] : nil
        return player.progress >= line.timestamp && (nextLine == nil || player.progress < nextLine!.timestamp)
    }
    
    private func cleanLyrics(_ lyrics: String) -> String {
        let pattern = "\\[\\d{2}:\\d{2}\\.\\d{2,3}\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: lyrics.utf16.count)
        return regex?.stringByReplacingMatches(in: lyrics, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? lyrics
    }
}

struct WidgetButtonStyle: ButtonStyle {
    var isRetro: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isRetro ? Color(red: 0.95, green: 0.9, blue: 0.7) : .white)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
