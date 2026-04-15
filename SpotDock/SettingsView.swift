import SwiftUI

struct SettingsView: View {
    @State private var selection: String? = "General"
    @Binding var miniPlayerController: MiniPlayerWindowController?

    let categories = [
        ("General", "gearshape"),
        ("Appearance", "paintpalette"),
        ("About", "info.circle")
    ]

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(miniPlayerController: $miniPlayerController)
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
    
    private func toggleMiniPlayer() {
        if miniPlayerController == nil {
            miniPlayerController = MiniPlayerWindowController()
            miniPlayerController?.showWindow(nil)
        } else {
            miniPlayerController?.toggle()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mini Player Toggle
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Mini Player")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Button(action: toggleMiniPlayer) {
                                Image(systemName: "pip.fill")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.bordered)
                            .help("Toggle Mini Player")
                        }
                        Text("Show or hide the floating mini player")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    Divider()

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
                        Text("Automatically start when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Show Lyrics by Default
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Show Lyrics by Default")
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle("", isOn: $showLyricsByDefault)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        Text("Open lyrics view when mini player launches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Account & Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SpotDock Account")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(player.isAuthenticated ? "Connected" : "Not connected")
                                    .font(.subheadline)
                                    .foregroundColor(player.isAuthenticated ? .green : .secondary)
                            }
                            Spacer()
                            if player.isAuthenticated {
                                Button("Logout") {
                                    player.logout()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red.opacity(0.8))
                            }
                        }
                        
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
    SettingsView(miniPlayerController: .constant(nil))
}
