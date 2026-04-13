import SwiftUI

struct SettingsView: View {
    @State private var selection: String? = "General"
    @State private var searchText = ""
    
    let categories = [
        ("General", "gear"),
        ("Theme", "paintpalette"),
        ("About", "info.circle"),
        ("Help", "questionmark.circle"),
        ("Quit", "power")
    ]
    
    var filteredCategories: [(String, String)] {
        if searchText.isEmpty {
            return categories
        } else {
            return categories.filter { $0.0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(filteredCategories, id: \.0) { category in
                        NavigationLink(value: category.0) {
                            Label(category.0, systemImage: category.1)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
            .frame(minWidth: 200)
        } detail: {
            if let selection = selection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(selection)
                            .font(.system(size: 24, weight: .bold))
                            .padding(.bottom, 10)
                        
                        switch selection {
                        case "General": GeneralSettingsView()
                        case "Theme": ThemeSettingsView()
                        case "About": AboutSettingsView()
                        case "Help": HelpSettingsView()
                        case "Quit": QuitSettingsView()
                        default: Text("Select a category")
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                Text("Select a category")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 750, height: 500)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showLyricsByDefault") private var showLyricsByDefault = false
    @AppStorage("groupSecondaryActions") private var groupSecondaryActions = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SettingsSection(title: "App Behavior") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Divider()
                Toggle("Show Lyrics by Default", isOn: $showLyricsByDefault)
                Divider()
                Toggle("Group Secondary Actions", isOn: $groupSecondaryActions)
                    .help("Clusters settings and power icons at the corners of the menu.")
            }
            
            SettingsSection(title: "Account") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Spotify Account")
                            .font(.body)
                        Text("Manage your authenticated session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Logout") {
                        SpotifyPlayer.shared.logout()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }
}

struct ThemeSettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = "Dark"
    @AppStorage("showAlbumArt") private var showAlbumArt = true
    @AppStorage("miniPlayerOpacity") private var miniPlayerOpacity = 0.9
    @AppStorage("menuAppLook") private var menuAppLook = "Default"
    @AppStorage("miniPlayerLook") private var miniPlayerLook = "Default"
    @AppStorage("miniPlayerCompactMode") private var miniPlayerCompactMode = false
    
    let themes = ["Dark", "Light", "Spotify Green", "Glassmorphism"]
    let looks = ["Default", "Retro Radio"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 20) {
                VStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(menuAppLook == "Retro Radio" ? Color(red: 0.2, green: 0.15, blue: 0.1) : Color(white: 0.15))
                        .frame(width: 120, height: 80)
                        .overlay(Text("Menu").font(.caption2).foregroundColor(.secondary))
                    Text("Menu App").font(.caption).bold()
                }
                
                VStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(miniPlayerLook == "Retro Radio" ? Color(red: 0.2, green: 0.15, blue: 0.1) : Color(white: 0.15))
                        .frame(width: 120, height: 80)
                        .overlay(Text("Mini").font(.caption2).foregroundColor(.secondary))
                    Text("Mini Player").font(.caption).bold()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)

            SettingsSection(title: "Interface") {
                Picker("Theme", selection: $selectedTheme) {
                    ForEach(themes, id: \.self) { Text($0) }
                }
                Divider()
                Picker("Menu App Look", selection: $menuAppLook) {
                    ForEach(looks, id: \.self) { Text($0) }
                }
                Divider()
                Picker("Mini Player Look", selection: $miniPlayerLook) {
                    ForEach(looks, id: \.self) { Text($0) }
                }
            }
            
            SettingsSection(title: "Mini Player Settings") {
                Toggle("Show Album Art", isOn: $showAlbumArt)
                Divider()
                Toggle("Compact Mode", isOn: $miniPlayerCompactMode)
                    .help("Shrinks album art to provide more room for text.")
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Opacity")
                        Spacer()
                        Text("\(Int(miniPlayerOpacity * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $miniPlayerOpacity, in: 0.5...1.0)
                }
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("SpotifyIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .shadow(radius: 5)
            
            VStack(spacing: 5) {
                Text("Spotify Widget")
                    .font(.title2)
                    .bold()
                Text("Version 1.0.0 (Build 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            SettingsSection(title: "Developer") {
                HStack {
                    Text("Created by")
                    Spacer()
                    Text("Pranab")
                        .foregroundColor(.secondary)
                }
                Divider()
                Text("A modern Spotify controller for macOS inspired by system widgets.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
            }
        }
    }
}

struct HelpSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Resources") {
                Link(destination: URL(string: "https://developer.spotify.com/documentation/web-api/")!) {
                    HStack {
                        Label("Spotify API Docs", systemImage: "safari")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                Divider()
                Link(destination: URL(string: "https://github.com/pranabkc/spotifywidget/issues")!) {
                    HStack {
                        Label("Report an Issue", systemImage: "ladybug")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct QuitSettingsView: View {
    var body: some View {
        SettingsSection(title: "Exit") {
            Text("Close the application and stop background polling.")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Spotify Widget")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
                .padding(.leading, 5)
            
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(15)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
    }
}

#Preview {
    SettingsView()
}
