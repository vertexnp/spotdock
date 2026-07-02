import SwiftUI
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    @Published var player = SpotifyPlayer.shared
    @Published var miniPlayerController: MiniPlayerWindowController?
    @Published var dynamicIslandController: DynamicIslandWindowController?

    init() {
        UserDefaults.standard.register(defaults: [
            "showDynamicIsland": true,
            "showMiniPlayer": true,
            "useUniversalNowPlaying": true
        ])
        SpotifyPlayer.shared.startPolling()
        DispatchQueue.main.async {
            self.setupControllers()
        }
    }
    
    func setupControllers() {
        if player.showMiniPlayer {
            if miniPlayerController == nil { miniPlayerController = MiniPlayerWindowController() }
            miniPlayerController?.showWindow(nil)
        } else { miniPlayerController?.close() }
        
        if player.showDynamicIsland {
            if dynamicIslandController == nil { dynamicIslandController = DynamicIslandWindowController() }
            dynamicIslandController?.window?.orderFrontRegardless()
        } else { dynamicIslandController?.close() }
    }
}

@main
struct SpotDockApp: App {
    @StateObject private var viewModel = AppViewModel()
    
    private var menuBarIcon: Image {
        if let nsImage = NSImage(named: "logo") {
            nsImage.isTemplate = true
            nsImage.size = NSSize(width: 18, height: 18)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "music.note")
    }

    var body: some Scene {
        // This is the Main Command Center Window
        WindowGroup {
            SettingsView(miniPlayerController: $viewModel.miniPlayerController, dynamicIslandController: $viewModel.dynamicIslandController)
                .frame(minWidth: 750, minHeight: 500)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // This is the Focused Menu Bar Player
        MenuBarExtra {
            SpotDockMenuView()
        } label: {
            menuBarIcon
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)
        
        .onChange(of: viewModel.player.showDynamicIsland) { _, _ in viewModel.setupControllers() }
        .onChange(of: viewModel.player.showMiniPlayer) { _, _ in viewModel.setupControllers() }
    }
}

struct SpotDockMenuView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @ObservedObject var universalPlayer = NowPlayingManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    private var isUniversal: Bool {
        player.useUniversalNowPlaying && !player.isPlaying && !universalPlayer.trackName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch themeManager.currentTheme {
                case .classic: classicMenuView
                case .minimal: minimalMenuView
                case .fanFav: fanFavMenuView
                }
            }
        }
        .padding(themeManager.currentTheme == .classic ? 8 : 16)
        .frame(width: themeManager.currentTheme == .classic ? 280 : 320)
    }

    // Reference the existing theme views defined in SpotifyApp.swift or move them here
    // For brevity, I am assuming the theme subviews like `classicMenuView` are kept in this file or reachable.
    // I will include the core theme views below to ensure the file is complete.

    private var currentTrackName: String { isUniversal ? universalPlayer.trackName : player.trackName }
    private var currentArtistName: String { isUniversal ? universalPlayer.artistName : player.artistName }
    private var currentIsPlaying: Bool { isUniversal ? universalPlayer.isPlaying : player.isPlaying }
    private var currentProgress: Double { isUniversal ? universalPlayer.progress : player.progress }
    private var currentDuration: Double { isUniversal ? universalPlayer.duration : player.duration }

    private var currentAlbumArt: some View {
        ZStack {
            if isUniversal {
                if let nsImage = universalPlayer.albumArt {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else { placeholderArt }
            } else {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholderArt }
            }
        }
    }

    private var placeholderArt: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note").foregroundColor(.white.opacity(0.4))
        }
    }

    private func togglePlay() {
        if isUniversal { universalPlayer.togglePlay() }
        else { Task { await player.togglePlay() } }
    }

    private func nextTrack() {
        if isUniversal { universalPlayer.nextTrack() }
        else { Task { await player.nextTrack() } }
    }

    private func previousTrack() {
        if isUniversal { universalPlayer.previousTrack() }
        else { Task { await player.previousTrack() } }
    }

    // MARK: - Theme Views (Restored for pure player experience)
    private var classicMenuView: some View {
        ZStack(alignment: .bottom) {
            currentAlbumArt.aspectRatio(1, contentMode: .fill).frame(width: 268, height: 268).clipped().cornerRadius(12)
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(currentTrackName).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(currentArtistName).font(.system(size: 12)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    }
                    if !isUniversal {
                        progressBar(color: .green, bgColor: .white.opacity(0.2)).padding(.horizontal, 16).frame(height: 4)
                    }
                    HStack(spacing: 16) {
                        Button(action: { previousTrack() }) { Image(systemName: "backward.end.fill").foregroundColor(.white) }.buttonStyle(.plain)
                        Button(action: { togglePlay() }) { Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill").font(.system(size: 24, weight: .bold)).foregroundColor(.white) }.buttonStyle(.plain)
                        Button(action: { nextTrack() }) { Image(systemName: "forward.end.fill").foregroundColor(.white) }.buttonStyle(.plain)
                    }.padding(.bottom, 12)
                }
                .background(LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .top, endPoint: .bottom))
            }
        }.frame(width: 268, height: 268)
    }

    private var minimalMenuView: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left Column: Album Art, Info, and Progress Bar
            VStack(alignment: .leading, spacing: 0) {
                // Album Art
                currentAlbumArt
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipped()
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .padding(.bottom, 10)
                
                // Track Info (Artist Name above Track Name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentArtistName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(currentTrackName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.bottom, 12)
                
                // Progress Bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(height: 3)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: currentDuration > 0 ? geo.size.width * CGFloat(currentProgress / currentDuration) : 0, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 3)
                    
                    HStack {
                        Text(formatTime(currentProgress))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(currentDuration))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Column: 2x2 Grid of Control Buttons
            VStack(spacing: 10) {
                // Top row - Lyrics toggle, Play/Pause
                HStack(spacing: 10) {
                    // Lyrics toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            player.showLyrics.toggle()
                        }
                    }) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(player.showLyrics ? .green : .primary.opacity(0.7))
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUniversal)
                    .opacity(isUniversal ? 0.3 : 1.0)
                    
                    // Play/Pause
                    Button(action: { togglePlay() }) {
                        Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary.opacity(0.9))
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                
                // Bottom row - Previous Track, Next Track
                HStack(spacing: 10) {
                    // Previous Track
                    Button(action: { previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary.opacity(0.7))
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    // Next Track
                    Button(action: { nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary.opacity(0.7))
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var fanFavMenuView: some View {
        VStack(spacing: 12) {
            currentAlbumArt.frame(width: 120, height: 120).clipShape(Circle())
            Text(currentTrackName).font(.system(size: 14, weight: .bold))
            HStack(spacing: 20) {
                Button(action: { previousTrack() }) { Image(systemName: "backward.circle") }.buttonStyle(.plain)
                Button(action: { togglePlay() }) { Image(systemName: currentIsPlaying ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle) }.buttonStyle(.plain)
                Button(action: { nextTrack() }) { Image(systemName: "forward.circle") }.buttonStyle(.plain)
            }
        }
    }

    private func progressBar(color: Color, bgColor: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(bgColor).frame(height: 4)
                Rectangle().fill(color).frame(width: currentDuration > 0 ? geo.size.width * CGFloat(currentProgress / currentDuration) : 0, height: 4)
            }
        }.frame(height: 4)
    }
}
