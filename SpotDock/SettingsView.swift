import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case dashboard = "Now Playing"
    case components = "Components"
    case appearance = "Appearance"
    case advanced = "Advanced"
    case about = "About"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "play.circle.fill"
        case .components: return "square.grid.2x2.fill"
        case .appearance: return "paintpalette.fill"
        case .advanced: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .dashboard
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @Binding var dynamicIslandController: DynamicIslandWindowController?

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SpotDock")
            .frame(minWidth: 200)
        } detail: {
            ZStack {
                Color(nsColor: NSColor.windowBackgroundColor).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerView
                        
                        Group {
                            switch selectedTab {
                            case .dashboard:
                                MainDashboardView()
                            case .components:
                                ComponentSettingsView(miniPlayerController: $miniPlayerController, dynamicIslandController: $dynamicIslandController)
                            case .appearance:
                                ThemeSettingsView()
                            case .advanced:
                                AdvancedSettingsView()
                            case .about:
                                AboutSettingsView()
                            }
                        }
                        .padding(30)
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.rawValue)
                .font(.system(size: 28, weight: .bold))
            Text(tabDescription)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var tabDescription: String {
        switch selectedTab {
        case .dashboard: return "Control your music and view track details."
        case .components: return "Manage Mini Player and Dynamic Island visibility."
        case .appearance: return "Customize the look and feel of SpotDock."
        case .advanced: return "System integration and login preferences."
        case .about: return "Information about SpotDock and its creator."
        }
    }
}

// MARK: - Dashboard
struct MainDashboardView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @ObservedObject var universalPlayer = NowPlayingManager.shared
    
    private var isUniversal: Bool {
        player.useUniversalNowPlaying && !universalPlayer.trackName.isEmpty && !player.isPlaying
    }
    
    private var trackName: String { isUniversal ? universalPlayer.trackName : player.trackName }
    private var artistName: String { isUniversal ? universalPlayer.artistName : player.artistName }
    
    var body: some View {
        VStack(spacing: 40) {
            // Adaptive Hero Section
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 40) {
                    albumArtView(size: 240)
                    infoAndControlsView
                }
                VStack(spacing: 30) {
                    albumArtView(size: 200)
                    infoAndControlsView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func albumArtView(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.1))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
            
            if isUniversal {
                if let img = universalPlayer.albumArt {
                    Image(nsImage: img).resizable().scaledToFill()
                } else { Image(systemName: "music.note").font(.system(size: size/3)).foregroundColor(.secondary) }
            } else {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note").font(.system(size: size/3)).foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    private var infoAndControlsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackName.isEmpty ? "No Track Playing" : trackName)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                
                Text(artistName.isEmpty ? "Unknown" : artistName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer().frame(height: 10)
            
            // Controls
            HStack(spacing: 25) {
                Button(action: { previous() }) {
                    Image(systemName: "backward.fill").font(.system(size: 22))
                }.buttonStyle(.plain)
                
                Button(action: { togglePlay() }) {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                        Image(systemName: (isUniversal ? universalPlayer.isPlaying : player.isPlaying) ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }.buttonStyle(.plain)
                
                Button(action: { next() }) {
                    Image(systemName: "forward.fill").font(.system(size: 22))
                }.buttonStyle(.plain)
            }
            
            if isUniversal {
                HStack(spacing: 6) {
                    Image(systemName: "safari").font(.caption)
                    Text("YouTube Browser Playback").font(.caption).fontWeight(.semibold)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 8)
            }
        }
    }
    
    private func togglePlay() {
        if isUniversal { universalPlayer.togglePlay() }
        else { Task { await player.togglePlay() } }
    }
    
    private func next() {
        if isUniversal { universalPlayer.nextTrack() }
        else { Task { await player.nextTrack() } }
    }
    
    private func previous() {
        if isUniversal { universalPlayer.previousTrack() }
        else { Task { await player.previousTrack() } }
    }
}

// MARK: - Components
struct ComponentSettingsView: View {
    @StateObject private var player = SpotifyPlayer.shared
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @Binding var dynamicIslandController: DynamicIslandWindowController?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Dynamic Island", subtitle: "Integrates playback into the top notch of your display.", icon: "dock.arrow.up.rectangle") {
                Toggle("", isOn: $player.showDynamicIsland)
                    .toggleStyle(.switch)
                    .onChange(of: player.showDynamicIsland) { _, newValue in
                        updateDI(newValue)
                    }
            }
            
            SettingCard(title: "Mini Player", subtitle: "A floating, draggable player window that stays on top.", icon: "macwindow") {
                Toggle("", isOn: $player.showMiniPlayer)
                    .toggleStyle(.switch)
                    .onChange(of: player.showMiniPlayer) { _, newValue in
                        updateMini(newValue)
                    }
            }
        }
    }
    
    private func updateDI(_ show: Bool) {
        if show {
            if dynamicIslandController == nil { dynamicIslandController = DynamicIslandWindowController() }
            dynamicIslandController?.showWindow(nil)
        } else { dynamicIslandController?.close() }
    }
    
    private func updateMini(_ show: Bool) {
        if show {
            if miniPlayerController == nil { miniPlayerController = MiniPlayerWindowController() }
            miniPlayerController?.showWindow(nil)
        } else { miniPlayerController?.close() }
    }
}

// MARK: - Advanced
struct AdvancedSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @StateObject private var player = SpotifyPlayer.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingCard(title: "Universal Now Playing", subtitle: "Show music from browsers (YouTube) when Spotify is idle.", icon: "safari") {
                Toggle("", isOn: $player.useUniversalNowPlaying).toggleStyle(.switch)
            }
            
            SettingCard(title: "System Integration", subtitle: "Fetch data directly from Spotify without using the API.", icon: "cpu") {
                Toggle("", isOn: $player.useSystemNowPlaying).toggleStyle(.switch)
            }
            
            SettingCard(title: "Launch at Login", subtitle: "Start SpotDock automatically when you log in.", icon: "arrow.up.right.square") {
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch)
            }
            
            Spacer().frame(height: 20)
            
            HStack {
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Label("Quit SpotDock", systemImage: "power")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}

// MARK: - Appearance
struct ThemeSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 20) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeCard(
                        theme: theme,
                        isSelected: themeManager.currentTheme == theme,
                        onTap: { themeManager.setTheme(theme) }
                    )
                }
            }
        }
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeColor)
                        .frame(height: 100)
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 10)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                    }
                }
                
                Text(theme.displayName)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var themeColor: Color {
        switch theme {
        case .classic: return Color(white: 0.15)
        case .minimal: return Color(white: 0.3)
        case .fanFav: return Color(red: 0.2, green: 0.3, blue: 0.2)
        }
    }
}

// MARK: - Helpers
struct SettingCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let content: () -> Content
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1))
                Image(systemName: icon).font(.system(size: 20)).foregroundColor(.accentColor)
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
            }
            
            Spacer()
            
            content()
        }
        .padding(16)
        .background(Color(nsColor: NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct AboutSettingsView: View {
    @StateObject private var updater = UpdateManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)
            
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "music.note.list").font(.system(size: 40)).foregroundColor(.accentColor)
            }
            
            VStack(spacing: 4) {
                Text("SpotDock").font(.system(size: 28, weight: .bold))
                Text("Version \(updater.currentVersion)").font(.system(size: 13)).foregroundColor(.secondary)
            }
            
            Text("A professional companion for your music journey on macOS. Seamlessly control Spotify and YouTube from your desktop.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
                .padding(.bottom, 10)
            
            // Updater UI Section
            VStack(spacing: 12) {
                if updater.updateAvailable {
                    VStack(spacing: 8) {
                        Text("New Version Available: \(updater.onlineVersion)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                        
                        if !updater.releaseNotes.isEmpty {
                            Text(updater.releaseNotes)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 300)
                                .padding(.bottom, 4)
                        }
                        
                        if updater.isDownloading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Downloading & installing update... App will restart.").font(.system(size: 12)).foregroundColor(.secondary)
                            }
                        } else {
                            Button(action: {
                                Task {
                                    await updater.startAutomaticUpdate()
                                }
                            }) {
                                Text("Update Automatically")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(Color.accentColor.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
                } else {
                    HStack(spacing: 12) {
                        if updater.isChecking {
                            ProgressView().controlSize(.small)
                            Text("Checking for updates...").font(.system(size: 13)).foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                Task {
                                    await updater.checkForUpdates()
                                }
                            }) {
                                Label("Check for Updates", systemImage: "arrow.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                
                if let error = updater.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                if let success = updater.successMessage {
                    Text(success)
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 120)
            
            Spacer()
            
            HStack {
                Text("Designed and Developed by")
                Text("Pranab").fontWeight(.bold)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Task {
                await updater.checkForUpdates(silent: true)
            }
        }
    }
}
