//
//  SpotifyApp.swift
//  Spotify
//

import SwiftUI
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    @Published var player = SpotifyPlayer.shared
    @Published var miniPlayerController: MiniPlayerWindowController?

    init() {
        // Start background polling in player
        SpotifyPlayer.shared.startPolling()

        // Show mini player on launch if already authenticated
        if SpotifyPlayer.shared.isAuthenticated {
            DispatchQueue.main.async {
                self.miniPlayerController = MiniPlayerWindowController()
                self.miniPlayerController?.showWindow(nil)
            }
        }
    }
}

@main
struct SpotifyApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        MenuBarExtra {
            SpotifyMenuView(miniPlayerController: $viewModel.miniPlayerController)
                .frame(width: themeManager.currentTheme == .classic ? 280 : 300)
                .padding(themeManager.currentTheme == .classic ? 8 : 16)
        } label: {
            Image("SpotifyIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: viewModel.player.isAuthenticated) { oldValue, newValue in
            if newValue && viewModel.miniPlayerController == nil {
                viewModel.miniPlayerController = MiniPlayerWindowController()
                viewModel.miniPlayerController?.showWindow(nil)
            }
        }

        Settings {
            SettingsView(miniPlayerController: $viewModel.miniPlayerController)
        }
    }
}

struct SpotifyMenuView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isHovering = false

    private var menuConfiguration: ThemeConfiguration {
        ThemeConfiguration.configuration(for: themeManager.currentTheme)
    }

    var body: some View {
        VStack(spacing: themeManager.currentTheme == .classic ? 8 : 14) {
            if player.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else if !player.isAuthenticated {
                loginView
            } else {
                // Show player content, with error overlay if needed
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
                .overlay(
                    player.error != nil ?
                    VStack {
                        Text("⚠️ \(player.error!)")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .top) : nil
                )
            }
            
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
                .onTapGesture {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .background(Color.clear)
        .cornerRadius(themeManager.currentTheme == .fanFav ? 12 : 0)
        .onAppear {
            Task { await player.fetchRecentlyPlayed() }
        }
    }
    private var loginView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Log in to Spotify")
                .font(.headline)

            Text("Sign in to load your account ID and show your recently played songs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Login") {
                player.login()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private var classicMenuView: some View {
        ZStack(alignment: .bottom) {
            // Album Art covering everything with 2px padding
            AsyncImage(url: URL(string: player.albumArtURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(width: 264, height: 264)
            .clipped()
            .cornerRadius(12)
            .padding(2)

            // Hover Controls
            if isHovering {
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 12) {
                        // Track Info
                        VStack(spacing: 2) {
                            Text(player.trackName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            Text(player.artistName)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .padding(.top, 45) // Increased padding by 5px to extend gradient higher

                        // Progress
                        progressBar(color: .green, bgColor: Color.white.opacity(0.2))
                            .padding(.horizontal, 16)
                            .frame(height: 4)

                        // Playback Controls
                        HStack(spacing: 16) {
                            // Shuffle
                            Button(action: { Task { await player.toggleShuffle() } }) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 14, weight: player.isShuffled ? .bold : .medium))
                                    .foregroundColor(player.isShuffled ? .green : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

                            controlButton(icon: "backward.end.fill", size: 16) { await player.previousTrack() }

                            Button(action: { Task { await player.togglePlay() } }) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)

                            controlButton(icon: "forward.end.fill", size: 16) { await player.nextTrack() }

                            // Repeat
                            Button(action: { Task { await player.cycleRepeat() } }) {
                                Image(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat")
                                    .font(.system(size: 14, weight: player.repeatMode != "off" ? .bold : .medium))
                                    .foregroundColor(player.repeatMode != "off" ? .green : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 12)
                    }
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
                    .transition(.opacity)
                    }
                    }        .frame(width: 264, height: 264)
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
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.15))
                        .overlay(Image(systemName: "music.note").font(.system(size: 24)).foregroundColor(.gray.opacity(0.5)))
                }
                .frame(width: 100, height: 100)
                .cornerRadius(12)
                .clipped()

                // Right side: Track info + visualizer
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.trackName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(player.artistName)
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
            HStack(spacing: 12) {
                // Shuffle
                Button(action: { Task { await player.toggleShuffle() } }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: player.isShuffled ? .bold : .semibold))
                        .foregroundColor(player.isShuffled ? .green : .white.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .background(Color(white: 0.18))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                minimalSquareButton(icon: "backward.fill", size: 48) { await player.previousTrack() }

                minimalSquareButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 56) { await player.togglePlay() }

                minimalSquareButton(icon: "forward.fill", size: 48) { await player.nextTrack() }

                // Repeat
                Button(action: { Task { await player.cycleRepeat() } }) {
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
        .padding()
    }

    private var immersiveVisualizer: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<32) { i in
                        let phase = Double(i) * 0.6 + context.date.timeIntervalSinceReferenceDate * 4
                        let barHeight = player.isPlaying
                            ? CGFloat(6 + sin(phase) * 6 + 10)
                            : CGFloat(3)
                        let opacity = player.isPlaying
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
                .frame(width: geo.size.width, height: player.isPlaying ? 28 : 3)
                .animation(.easeInOut(duration: 0.4), value: player.isPlaying)
            }
        }
        .frame(height: player.isPlaying ? 28 : 3)
        .clipped()
    }

    private var audioWaveform: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { (timeline: TimelineViewDefaultContext) -> AnyView in
            AnyView(
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let width = size.width
                    let height = size.height
                    
                    let rows = 8
                    let cols = 80
                    let spacingX = width / CGFloat(cols)
                    
                    for row in 0..<rows {
                        let rowProgress = CGFloat(row) / CGFloat(rows)
                        let z = Double(row) * 0.4
                        
                        // Vibrant purple/magenta color inspired by the user's image
                        let baseColor = Color(red: 0.75, green: 0.15, blue: 0.95)
                        let opacity = (0.2 + (1.0 - rowProgress) * 0.8) * (player.isPlaying ? 1.0 : 0.25)
                        
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
                            
                            amplitude *= (player.isPlaying ? 1.0 : 0.08)
                            
                            // Vertical position with perspective-like row shift
                            let y = (height * 0.5) + (CGFloat(amplitude) * height * 0.45) + (rowProgress * 12 - 6)
                            
                            let dotSize: CGFloat = 1.4 - (rowProgress * 0.4)
                            
                            // Draw the main point
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)),
                                with: .color(baseColor.opacity(opacity))
                            )
                            
                            // Add vertical "shadow" points for texture depth
                            if player.isPlaying && row % 2 == 0 {
                                context.fill(
                                    Path(ellipseIn: CGRect(x: x - dotSize/2, y: y + 1.5 - dotSize/2, width: dotSize, height: dotSize)),
                                    with: .color(baseColor.opacity(opacity * 0.4))
                                )
                            }
                        }
                    }
                }
            )
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.4), value: player.isPlaying)
    }

    private func minimalSquareButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
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
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            ZStack(alignment: .bottom) {
                VStack(spacing: 12) {

                    // Vinyl record
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
                        AsyncImage(url: URL(string: player.albumArtURL)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color(white: 0.15))
                                .overlay(Image(systemName: "music.note").font(.system(size: 16)).foregroundColor(.gray))
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                        Circle().fill(Color(white: 0.05)).frame(width: 5, height: 5)
                    }
                    .onChange(of: context.date) { _, _ in
                        if player.isPlaying {
                            vinylRotationAngle += 1.5
                            if vinylRotationAngle >= 360 {
                                vinylRotationAngle -= 360
                            }
                        }
                    }

                    // Track info
                    VStack(spacing: 3) {
                        Text(player.trackName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(player.artistName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 3).clipShape(Capsule())
                            Rectangle().fill(Color.white.opacity(0.6))
                                .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 3)

                    // Controls
                    HStack(spacing: 16) {
                        // Shuffle
                        Button(action: { Task { await player.toggleShuffle() } }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 12, weight: player.isShuffled ? .bold : .medium))
                                .foregroundColor(player.isShuffled ? Color(red: 0.9, green: 1.0, blue: 0.7) : .white.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Button(action: { Task { await player.previousTrack() } }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

                        Button(action: { Task { await player.togglePlay() } }) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color(white: 0.1)))
                        }
                        .buttonStyle(.plain)

                        Button(action: { Task { await player.nextTrack() } }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

                        // Repeat
                        Button(action: { Task { await player.cycleRepeat() } }) {
                            Image(systemName: player.repeatMode == "track" ? "repeat.1" : "repeat")
                                .font(.system(size: 12, weight: player.repeatMode != "off" ? .bold : .medium))
                                .foregroundColor(player.repeatMode != "off" ? Color(red: 0.9, green: 1.0, blue: 0.7) : .white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                    Task {
                        await player.fetchRecentlyPlayed()
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 64)
                .frame(width: 220)
                .cornerRadius(16)

                // Recently Played - positioned at bottom of ZStack
                if !player.recommendations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(player.recommendations) { track in
                                AsyncImage(url: URL(string: track.albumArtURL)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(white: 0.15))
                                }
                                .frame(width: 52, height: 52)
                                .cornerRadius(8)
                                .clipped()
                            }
                        }
                    }
                    .frame(height: 52)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
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
                    .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 4)
            }
        }
        .frame(height: 4)
    }
    
    private func controlButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
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
