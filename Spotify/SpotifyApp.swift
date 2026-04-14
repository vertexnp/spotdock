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
    
    var body: some Scene {
        MenuBarExtra {
            SpotifyMenuView(miniPlayerController: $viewModel.miniPlayerController)
                .frame(width: 300)
                .padding()
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
            SettingsView()
        }
    }
}

struct SpotifyMenuView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @StateObject private var themeManager = ThemeManager.shared

    private var menuConfiguration: ThemeConfiguration {
        ThemeConfiguration.configuration(for: themeManager.currentTheme)
    }

    var body: some View {
        VStack(spacing: 14) {
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

            footerView
        }
        .background(themeManager.currentTheme == .classic ? Color.clear : Color.clear)
        .cornerRadius(themeManager.currentTheme == .fanFav ? 12 : 0)
        .onReceive(themeManager.$currentTheme) { _ in
            // React to theme changes
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
        VStack(spacing: 14) {
            // Album Art
            AsyncImage(url: URL(string: player.albumArtURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
            }
            .frame(width: 250, height: 250)
            .cornerRadius(8)

            // Track Info
            VStack(spacing: 2) {
                Text(player.trackName)
                    .font(.headline)
                    .lineLimit(1)
                Text(player.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            // Progress Bar
            progressBar(color: .green, bgColor: Color.gray.opacity(0.3))

            HStack {
                Text(formatTime(player.progress))
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(formatTime(player.duration))
                    .font(.caption2).foregroundColor(.secondary)
            }

            // Controls
            HStack(spacing: 32) {
                controlButton(icon: "backward.end.fill", size: 20) { await player.previousTrack() }

                Button(action: { Task { await player.togglePlay() } }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                controlButton(icon: "forward.end.fill", size: 20) { await player.nextTrack() }
            }
        }
    }

    private var minimalMenuView: some View {
        VStack(spacing: 12) {
            // Album Art - Larger and more prominent
            AsyncImage(url: URL(string: player.albumArtURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "music.note").font(.largeTitle).foregroundColor(.gray))
            }
            .frame(width: 260, height: 260)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            // Track Info - Clean and centered
            VStack(spacing: 4) {
                Text(player.trackName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(player.artistName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            // Progress Bar - Minimal style
            progressBar(color: .white, bgColor: Color.white.opacity(0.2))

            HStack {
                Text(formatTime(player.progress))
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(formatTime(player.duration))
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
            }

            // Controls - Minimal circular buttons
            HStack(spacing: 28) {
                minimalControlButton(icon: "backward.fill", size: 18) { await player.previousTrack() }

                Button(action: { Task { await player.togglePlay() } }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 48, height: 48)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                minimalControlButton(icon: "forward.fill", size: 18) { await player.nextTrack() }
            }
        }
        .padding()
    }

    private var vinylMenuRotation: Double {
        guard player.duration > 0 else { return 0 }
        return (player.progress / player.duration) * 360
    }

    private var fanFavMenuView: some View {
        VStack(spacing: 12) {
            // Vinyl record (smaller for menu bar)
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
                    .rotationEffect(.degrees(vinylMenuRotation))
                
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
            HStack(spacing: 20) {
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
            }
        }
        .padding()
        .frame(width: 220)
        .background(
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }

    @AppStorage("groupSecondaryActions") private var groupSecondaryActions = true

    private var footerView: some View {
        HStack {
            // Left Cluster
            HStack(spacing: groupSecondaryActions ? 12 : 16) {
                Button(action: {
                    if miniPlayerController == nil {
                        miniPlayerController = MiniPlayerWindowController()
                    }
                    miniPlayerController?.toggle()
                }) {
                    Image(systemName: "pip.fill")
                        .font(.system(size: 14))
                        .foregroundColor(menuConfiguration.menuAccentColor.opacity(miniPlayerController?.window?.isVisible == true ? 1.0 : 0.7))
                }
                .buttonStyle(.plain)
                .help("Toggle Mini Player")

                Button(action: { Task { await player.refreshPlayerData() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(menuConfiguration.menuTextColor.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(groupSecondaryActions && themeManager.currentTheme == .classic ? 8 : 0)
            .background(groupSecondaryActions && themeManager.currentTheme == .classic ? menuConfiguration.menuTextColor.opacity(0.08) : Color.clear)
            .cornerRadius(groupSecondaryActions && themeManager.currentTheme == .classic ? 8 : 0)

            Spacer()

            // Right Cluster
            HStack(spacing: groupSecondaryActions ? 12 : 16) {
                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(menuConfiguration.menuTextColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                } else {
                    Button(action: {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(menuConfiguration.menuTextColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }

                Button(action: {
                    player.logout()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(menuConfiguration.menuTextColor.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Logout")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(groupSecondaryActions && themeManager.currentTheme == .classic ? 8 : 0)
            .background(groupSecondaryActions && themeManager.currentTheme == .classic ? menuConfiguration.menuTextColor.opacity(0.08) : Color.clear)
            .cornerRadius(groupSecondaryActions && themeManager.currentTheme == .classic ? 8 : 0)
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
    
    private func retroControlButton(icon: String, size: CGFloat = 25, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size + 15, height: size + 15)
                    .shadow(radius: 2)

                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .black))
                    .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.3))
            }
        }
        .buttonStyle(.plain)
    }

    private func minimalControlButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
