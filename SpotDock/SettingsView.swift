import SwiftUI

struct SettingsView: View {
    @State private var selection: String? = "General"
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @Binding var dynamicIslandController: DynamicIslandWindowController?

    let categories = [
        ("General", "gearshape"),
        ("Appearance", "paintpalette"),
        ("About", "info.circle")
    ]

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(miniPlayerController: $miniPlayerController, dynamicIslandController: $dynamicIslandController)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("General" as String?)

            ThemeSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag("Appearance" as String?)

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag("About" as String?)
        }
        .frame(width: 480, height: 380)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showLyricsByDefault") private var showLyricsByDefault = false
    @StateObject private var player = SpotifyPlayer.shared
    @Binding var miniPlayerController: MiniPlayerWindowController?
    @Binding var dynamicIslandController: DynamicIslandWindowController?
    
    private func updateMiniPlayerVisibility(_ show: Bool) {
        if show {
            if miniPlayerController == nil {
                miniPlayerController = MiniPlayerWindowController()
            }
            miniPlayerController?.showWindow(nil)
        } else {
            miniPlayerController?.close()
        }
    }

    private func updateDynamicIslandVisibility(_ show: Bool) {
        if show {
            if dynamicIslandController == nil {
                dynamicIslandController = DynamicIslandWindowController()
            }
            dynamicIslandController?.showWindow(nil)
        } else {
            dynamicIslandController?.close()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Components Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Components")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        // Mini Player Toggle
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Floating Mini Player")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Toggle("", isOn: $player.showMiniPlayer)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .onChange(of: player.showMiniPlayer) { _, newValue in
                                        updateMiniPlayerVisibility(newValue)
                                    }
                            }
                            Text("Show a floating, draggable player window on your desktop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: NSColor.controlBackgroundColor))
                        .cornerRadius(10)

                        // Dynamic Island Toggle
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Dynamic Island")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Toggle("", isOn: $player.showDynamicIsland)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .onChange(of: player.showDynamicIsland) { _, newValue in
                                        updateDynamicIslandVisibility(newValue)
                                    }
                            }
                            Text("Integrate the player into the top notch of your display")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    Divider()
                    
                    // Features Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Features")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        // Universal Now Playing
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Universal Now Playing")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Toggle("", isOn: $player.useUniversalNowPlaying)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            Text("Show music from browsers (YouTube) when Spotify is idle. Mini player remains Spotify-only.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: NSColor.controlBackgroundColor))
                        .cornerRadius(10)

                        // Launch at Login
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Launch at Login")
                                    .font(.body)
                                    .fontWeight(.medium)
                                Spacer()
                                Toggle("", isOn: $launchAtLogin)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }

                    Divider()

                    // System Now Playing
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Use System Now Playing")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $player.useSystemNowPlaying)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        Text("Fetch data directly from the Spotify app (no API, bypasses rate limits)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Actions Section
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        HStack {
                            Spacer()
                            Button("Quit SpotDock") {
                                NSApplication.shared.terminate(nil)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
}

struct ThemeSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Theme Selection Cards
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: themeManager.currentTheme == theme,
                            onTap: { themeManager.setTheme(theme) }
                        )
                    }
                }
            }
            .padding(20)

            Spacer()
        }
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Mini preview
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeBackgroundColor)
                        .frame(width: 120, height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                        )

                    // Mini content preview
                    HStack(spacing: 0) {
                        // Album art placeholder
                        Rectangle()
                            .fill(themeAccentColor.opacity(0.3))
                            .frame(width: 32)
                            .clipped()

                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeTextColor)
                                .frame(width: 45, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeTextColor.opacity(0.5))
                                .frame(width: 35, height: 3)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(themeTextColor.opacity(0.6)).frame(width: 4, height: 4)
                                Circle().fill(themeTextColor).frame(width: 6, height: 6)
                                Circle().fill(themeTextColor.opacity(0.6)).frame(width: 4, height: 4)
                            }
                            .padding(.bottom, 6)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                    }
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(theme.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var themeBackgroundColor: Color {
        switch theme {
        case .classic:
            return Color(white: 0.12)
        case .minimal:
            return Color(white: 0.12)
        case .fanFav:
            return Color(red: 0.15, green: 0.25, blue: 0.15)
        }
    }

    private var themeTextColor: Color {
        switch theme {
        case .fanFav:
            return Color(red: 0.9, green: 1.0, blue: 0.7)
        default:
            return .white
        }
    }

    private var themeAccentColor: Color {
        switch theme {
        case .classic:
            return .green
        case .minimal:
            return .white
        case .fanFav:
            return Color(red: 0.9, green: 1.0, blue: 0.7)
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(spacing: 4) {
                Text("SpotDock")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("A modern music controller for macOS")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Divider()

            HStack {
                Text("Built by")
                Spacer()
                Text("Pranab")
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }
}

#Preview {
    SettingsView(miniPlayerController: .constant(nil), dynamicIslandController: .constant(nil))
}
