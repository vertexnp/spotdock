//
//  SpotifyApp.swift
//  SpotDock
//

import SwiftUI
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    @Published var player = SpotifyPlayer.shared
    @Published var miniPlayerController: MiniPlayerWindowController?
    @Published var dynamicIslandController: DynamicIslandWindowController?

    init() {
        // Register defaults to ensure components are on by default on first run
        UserDefaults.standard.register(defaults: [
            "showDynamicIsland": true,
            "showMiniPlayer": true,
            "useUniversalNowPlaying": true
        ])

        // Start background polling in player
        SpotifyPlayer.shared.startPolling()

        // Initialize windows based on user preferences on launch
        DispatchQueue.main.async {
            self.setupControllers()
        }
    }
    
    func setupControllers() {
        // Handle Mini Player
        if player.showMiniPlayer {
            if miniPlayerController == nil {
                miniPlayerController = MiniPlayerWindowController()
            }
            miniPlayerController?.showWindow(nil)
        } else {
            miniPlayerController?.close()
        }
        
        // Handle Dynamic Island
        if player.showDynamicIsland {
            if dynamicIslandController == nil {
                dynamicIslandController = DynamicIslandWindowController()
            }
            dynamicIslandController?.window?.orderFrontRegardless()
        } else {
            dynamicIslandController?.close()
        }
    }
}

@main
struct SpotDockApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    
    private var menuBarIcon: Image {
        if let nsImage = NSImage(named: "logo") {
            nsImage.isTemplate = true
            nsImage.size = NSSize(width: 18, height: 18)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "music.note")
    }

    var body: some Scene {
        MenuBarExtra {
            ZStack(alignment: .topTrailing) {
                SpotDockMenuView(miniPlayerController: $viewModel.miniPlayerController, dynamicIslandController: $viewModel.dynamicIslandController)
                    .frame(width: themeManager.currentTheme == .classic ? 280 : 300)
                    .padding(themeManager.currentTheme == .classic ? 8 : 16)

                // Distinct top-right settings button for modern themes
                if themeManager.currentTheme != .classic {
                    SettingsLink {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        } label: {
            menuBarIcon
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: viewModel.player.isAuthenticated) { oldValue, newValue in
            if newValue {
                viewModel.setupControllers()
            }
        }
        .onChange(of: viewModel.player.showDynamicIsland) { oldValue, newValue in
            viewModel.setupControllers()
        }
        .onChange(of: viewModel.player.showMiniPlayer) { oldValue, newValue in
            viewModel.setupControllers()
        }

        Settings {
            SettingsView(miniPlayerController: $viewModel.miniPlayerController, dynamicIslandController: $viewModel.dynamicIslandController)
        }
    }
}

struct SpotDockMenuView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @ObservedObject var universalPlayer = NowPlayingManager.shared
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @Binding var dynamicIslandController: DynamicIslandWindowController?
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isHovering = false

    private var isSpotifySource: Bool {
        universalPlayer.bundleID == "com.spotify.client"
    }

    private var isUniversalActive: Bool {
        player.useUniversalNowPlaying && !universalPlayer.trackName.isEmpty && !player.isPlaying
    }

    private var currentTrackName: String {
        isUniversalActive ? universalPlayer.trackName : player.trackName
    }

    private var currentArtistName: String {
        isUniversalActive ? universalPlayer.artistName : player.artistName
    }

    private var currentIsPlaying: Bool {
        isUniversalActive ? universalPlayer.isPlaying : player.isPlaying
    }

    private var currentProgress: Double {
        isUniversalActive ? universalPlayer.progress : player.progress
    }

    private var currentDuration: Double {
        isUniversalActive ? universalPlayer.duration : player.duration
    }

    private var currentAlbumArt: some View {
        ZStack {
            if isUniversalActive {
                if let nsImage = universalPlayer.albumArt {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholderArt(size: 40)
                }
            } else {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderArt(size: 40)
                }
            }
        }
    }

    private func placeholderArt(size: CGFloat) -> some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note")
                .font(.system(size: size))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var menuConfiguration: ThemeConfiguration {
        ThemeConfiguration.configuration(for: themeManager.currentTheme)
    }

    private func togglePlay() {
        if isUniversalActive {
            universalPlayer.togglePlay()
        } else {
            Task { await player.togglePlay() }
        }
    }

    private func nextTrack() {
        if isUniversalActive {
            universalPlayer.nextTrack()
        } else {
            Task { await player.nextTrack() }
        }
    }

    private func previousTrack() {
        if isUniversalActive {
            universalPlayer.previousTrack()
        } else {
            Task { await player.previousTrack() }
        }
    }

    var body: some View {
        VStack(spacing: themeManager.currentTheme == .classic ? 8 : 14) {
            // Show player content
            Group {
                switch themeManager.currentTheme {
                case .classic:
                    classicMenuView
                case .minimal:
                    minimalMenuView
                case .fanFav:
                    fanFavMenuView
                }
            }
            
            if themeManager.currentTheme == .classic {
                Divider()

                HStack {
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(menuConfiguration.menuTextColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
        }
        .background(Color.clear)
        .cornerRadius(themeManager.currentTheme == .fanFav ? 12 : 0)
        .onAppear {
            if isSpotifySource {
                Task { 
                    // OAuth-dependent fetches removed
                }
            }
        }
    }
    private var classicMenuView: some View {
        ZStack(alignment: .bottom) {
            // Album Art covering everything
            currentAlbumArt
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 268, height: 268) // Slightly larger to ensure full coverage
            .clipped()
            .cornerRadius(12)

            // Hover Controls
            if isHovering {
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 12) {
                        // Track Info
                        VStack(spacing: 2) {
                            Text(currentTrackName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            Text(currentArtistName)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .padding(.top, 45)
                        .padding(.horizontal, 16) // Padding for text but not gradient

                        // Progress
                        if !isUniversalActive {
                            progressBar(color: .green, bgColor: Color.white.opacity(0.2))
                                .padding(.horizontal, 16)
                                .frame(height: 4)
                        }

                        // Playback Controls
                        if !isUniversalActive {
                            HStack(spacing: 16) {
                                // Shuffle
                                if isSpotifySource {
                                    Button(action: { Task { await player.toggleShuffle() } }) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 14, weight: player.isShuffled ? .bold : .medium))
                                            .foregroundColor(player.isShuffled ? .green : .white.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Spacer().frame(width: 14)
                                }

                                controlButton(icon: "backward.end.fill", size: 16) { previousTrack() }

                                Button(action: { togglePlay() }) {
                                    Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)

                                controlButton(icon: "forward.end.fill", size: 16) { nextTrack() }

                                // Repeat
                                if isSpotifySource {
                                    Button(action: { Task { await player.toggleRepeat() } }) {
                                        Image(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat")
                                            .font(.system(size: 14, weight: player.repeatMode != "off" ? .bold : .medium))
                                            .foregroundColor(player.repeatMode != "off" ? .green : .white.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Spacer().frame(width: 14)
                                }
                            }
                            .padding(.bottom, 12)
                        } else {
                            Text("Browser Playback")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.bottom, 20)
                        }
                    }
                    .frame(maxWidth: .infinity) // Ensure the controls VStack fills the width
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.4), location: 0.2),
                                .init(color: .black.opacity(0.85), location: 0.5),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(maxWidth: .infinity) // Outer VStack fills width too
                .transition(.opacity)
                .cornerRadius(12) // Round the corners of the overlay to match album art
            }
        }
        .frame(width: 268, height: 268)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    private var minimalMenuView: some View {
        VStack(spacing: 16) {
            // Top section: Album art left, track info + visualizer right
            HStack(spacing: 16) {
                // Album Art
                currentAlbumArt
                .frame(width: 100, height: 100)
                .cornerRadius(12)
                .clipped()

                // Right side: Track info + visualizer
                VStack(alignment: .leading, spacing: 0) {
                    Text(currentTrackName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(currentArtistName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    // Audio waveform visualizer
                    audioWaveform
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Controls - Square buttons with rounded corners
            if !isUniversalActive {
                HStack(spacing: 12) {
                    // Shuffle
                    if isSpotifySource {
                        Button(action: { Task { await player.toggleShuffle() } }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 16, weight: player.isShuffled ? .bold : .semibold))
                                .foregroundColor(player.isShuffled ? .green : .white.opacity(0.7))
                                .frame(width: 40, height: 40)
                                .background(Color(white: 0.18))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }

                    minimalSquareButton(icon: "backward.fill", size: 48) { previousTrack() }

                    minimalSquareButton(icon: currentIsPlaying ? "pause.fill" : "play.fill", size: 56) { togglePlay() }

                    minimalSquareButton(icon: "forward.fill", size: 48) { nextTrack() }

                    // Repeat
                    if isSpotifySource {
                        Button(action: { Task { await player.toggleRepeat() } }) {
                            Image(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat")
                                .font(.system(size: 16, weight: player.repeatMode != "off" ? .bold : .semibold))
                                .foregroundColor(player.repeatMode != "off" ? .green : .white.opacity(0.7))
                                .frame(width: 40, height: 40)
                                .background(Color(white: 0.18))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Browser Playback")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 10)
            }
        }
        .padding()
    }

    private var immersiveVisualizer: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<32) { i in
                        let phase = Double(i) * 0.6 + context.date.timeIntervalSinceReferenceDate * 4
                        let barHeight = currentIsPlaying
                            ? CGFloat(6 + sin(phase) * 6 + 10)
                            : CGFloat(3)
                        let opacity = currentIsPlaying
                            ? 0.3 + sin(phase + Double(i) * 0.3) * 0.3
                            : 0.15
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(opacity * 0.5),
                                        Color.white.opacity(opacity),
                                        Color.white.opacity(opacity * 0.4)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: max(0, (geo.size.width - 62) / 32), height: barHeight)
                            .cornerRadius(1.5)
                    }
                }
                .frame(width: geo.size.width, height: currentIsPlaying ? 28 : 3)
                .animation(.easeInOut(duration: 0.4), value: currentIsPlaying)
            }
        }
        .frame(height: currentIsPlaying ? 28 : 3)
        .clipped()
    }

    private var audioWaveform: some View {
        // Reduced frequency from 0.04 (25fps) to 0.1 (10fps)
        TimelineView(.animation(minimumInterval: 0.1)) { (timeline: TimelineViewDefaultContext) -> AnyView in
            AnyView(
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let width = size.width
                    let height = size.height
                    
                    let rows = 8
                    // Reduced from 80 to 40 columns (half the dots, half the calculations)
                    let cols = 40
                    let spacingX = width / CGFloat(cols)
                    
                    for row in 0..<rows {
                        let rowProgress = CGFloat(row) / CGFloat(rows)
                        let z = Double(row) * 0.4
                        
                        // Vibrant purple/magenta color inspired by the user's image
                        let baseColor = Color(red: 0.75, green: 0.15, blue: 0.95)
                        let opacity = (0.2 + (1.0 - rowProgress) * 0.8) * (currentIsPlaying ? 1.0 : 0.25)
                        
                        // Skip expensive loops if not playing and menu is likely in background
                        if !currentIsPlaying && rowProgress > 0.3 { continue }
                        
                        for col in 0...cols {
                            let xProgress = Double(col) / Double(cols)
                            let x = CGFloat(col) * spacingX
                            
                            // Multi-wave interference for organic, topographic motion
                            let wave1 = sin(xProgress * 7.0 + t * 2.2 + z)
                            let wave2 = sin(xProgress * 3.5 - t * 1.8 + z * 1.5)
                            let wave3 = cos(xProgress * 12.0 + t * 3.5 + Double(row))
                            
                            var amplitude = (wave1 * 0.4 + wave2 * 0.35 + wave3 * 0.25)
                            // Dampen amplitude based on distance from center for a "ridge" effect
                            let edgeDamping = 1.0 - pow(abs(xProgress - 0.5) * 2.0, 2.0)
                            amplitude *= edgeDamping
                            
                            amplitude *= (currentIsPlaying ? 1.0 : 0.08)
                            
                            // Vertical position with perspective-like row shift
                            let y = (height * 0.5) + (CGFloat(amplitude) * height * 0.45) + (rowProgress * 12 - 6)
                            
                            let dotSize: CGFloat = 1.6 - (rowProgress * 0.4)
                            
                            // Draw the main point
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)),
                                with: .color(baseColor.opacity(opacity))
                            )
                        }
                    }
                }
            )
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.4), value: currentIsPlaying)
    }

    private func minimalSquareButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: { action() }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: size, height: size)
                .background(Color(white: 0.18))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @State private var vinylRotationAngle: Double = 0

    private var fanFavMenuView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 12) {
                vinylRecordView
                fanFavTrackInfoView
                
                if !isUniversalActive {
                    progressBar(color: .white.opacity(0.6), bgColor: Color.white.opacity(0.15))
                        .frame(height: 3)
                    fanFavControlsView
                } else {
                    Text("Browser Playback")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 64)
            .frame(width: 220)
            .cornerRadius(16)
        }
    }

    private var vinylRecordView: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(white: 0.08), Color(white: 0.15), Color(white: 0.08),
                                Color(white: 0.12), Color(white: 0.08), Color(white: 0.14)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(vinylRotationAngle))

                // Grooves
                ForEach(0..<8) { i in
                    Circle()
                        .stroke(Color(white: 0.05).opacity(0.4), lineWidth: 0.5)
                        .frame(width: CGFloat(30 + i * 11), height: CGFloat(30 + i * 11))
                }

                // Highlight arc
                Circle()
                    .trim(from: 0.1, to: 0.35)
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(vinylRotationAngle))

                // Album art center
                currentAlbumArt
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                Circle().fill(Color(white: 0.05)).frame(width: 5, height: 5)
            }
            .onChange(of: context.date) { _, _ in
                if currentIsPlaying {
                    vinylRotationAngle += 1.5
                    if vinylRotationAngle >= 360 { vinylRotationAngle -= 360 }
                }
            }
        }
    }

    private var fanFavTrackInfoView: some View {
        VStack(spacing: 3) {
            Text(currentTrackName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(currentArtistName)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var fanFavControlsView: some View {
        HStack(spacing: 16) {
            // Shuffle
            if isSpotifySource {
                Button(action: { Task { await player.toggleShuffle() } }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: player.isShuffled ? .bold : .medium))
                        .foregroundColor(player.isShuffled ? Color(red: 0.9, green: 1.0, blue: 0.7) : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            Button(action: { previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button(action: { togglePlay() }) {
                Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(white: 0.1)))
            }
            .buttonStyle(.plain)

            Button(action: { nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            // Repeat
            if isSpotifySource {
                Button(action: { Task { await player.toggleRepeat() } }) {
                    Image(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat")
                        .font(.system(size: 12, weight: player.repeatMode != "off" ? .bold : .medium))
                        .foregroundColor(player.repeatMode != "off" ? Color(red: 0.9, green: 1.0, blue: 0.7) : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func progressBar(color: Color, bgColor: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(bgColor)
                    .frame(height: 4)
                Rectangle()
                    .fill(color)
                    .frame(width: currentDuration > 0 ? geo.size.width * CGFloat(currentProgress / currentDuration) : 0, height: 4)
            }
        }
        .frame(height: 4)
    }
    
    private func controlButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: { action() }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
