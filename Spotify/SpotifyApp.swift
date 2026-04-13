//
//  SpotifyApp.swift
//  Spotify
//

import SwiftUI
import Combine

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
    
    @AppStorage("menuAppLook") private var menuAppLook = "Default"

    var body: some View {
        VStack(spacing: 14) {
            if player.isLoading {
                ProgressView()
                    .frame(height: 200)
            } else if !player.isAuthenticated {
                loginView
            } else if let error = player.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                if menuAppLook == "Retro Radio" {
                    retroMenuView
                } else {
                    defaultMenuView
                }
            }

            Divider()
                .opacity(menuAppLook == "Retro Radio" ? 0.2 : 1.0)

            footerView
        }
        .background(menuAppLook == "Retro Radio" ? Color(red: 0.15, green: 0.1, blue: 0.05) : Color.clear)
        .cornerRadius(menuAppLook == "Retro Radio" ? 12 : 0)
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
    
    private var defaultMenuView: some View {
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
    
    private var retroMenuView: some View {
        VStack(spacing: 14) {
            // Analog Look Display
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.4, green: 0.2, blue: 0.1), lineWidth: 4)
                    )
                
                VStack(spacing: 8) {
                    Text(player.trackName.uppercased())
                        .font(.custom("Courier-Bold", size: 18))
                        .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.3))
                        .lineLimit(1)
                    
                    Text(player.artistName.uppercased())
                        .font(.custom("Courier", size: 14))
                        .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.3).opacity(0.8))
                        .lineLimit(1)
                    
                    // Simple Spectrum Analyzer Look
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<15) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color(red: 0.9, green: 0.4, blue: 0.3))
                                .frame(width: 4, height: player.isPlaying ? CGFloat.random(in: 5...30) : 5)
                                .animation(.easeInOut(duration: 0.2).repeatForever(), value: player.isPlaying)
                        }
                    }
                    .frame(height: 35)
                }
                .padding()
            }
            .frame(height: 120)
            
            // Retro Progress
            VStack(spacing: 4) {
                progressBar(color: Color(red: 0.9, green: 0.4, blue: 0.3), bgColor: Color.black)
                
                HStack {
                    Text(formatTime(player.progress))
                    Spacer()
                    Text("SW / AM / FM")
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.custom("Courier", size: 10))
                .foregroundColor(Color(red: 0.9, green: 0.4, blue: 0.3).opacity(0.6))
            }

            // Analog Controls
            HStack(spacing: 25) {
                retroControlButton(icon: "backward.fill") { await player.previousTrack() }
                
                retroControlButton(icon: player.isPlaying ? "stop.fill" : "play.fill", size: 35) { await player.togglePlay() }
                
                retroControlButton(icon: "forward.fill") { await player.nextTrack() }
            }
            .padding(.vertical, 10)
        }
        .padding()
        .background(Color(red: 0.2, green: 0.15, blue: 0.1))
        .cornerRadius(8)
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
                        .foregroundColor(miniPlayerController?.window?.isVisible == true ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Mini Player")

                Button(action: { Task { await player.refreshPlayerData() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(groupSecondaryActions ? 8 : 0)
            .background(groupSecondaryActions ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(groupSecondaryActions ? 8 : 0)

            Spacer()

            // Right Cluster
            HStack(spacing: groupSecondaryActions ? 12 : 16) {
                if #available(macOS 13.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                } else {
                    Button(action: {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }

                Button(action: {
                    player.logout()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Logout")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(groupSecondaryActions ? 8 : 0)
            .background(groupSecondaryActions ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(groupSecondaryActions ? 8 : 0)
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
