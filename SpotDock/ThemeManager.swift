//
//  ThemeManager.swift
//  Spotify
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case minimal = "Minimal"
    case fanFav = "Fan Fav"
    
    var id: String { self.rawValue }
    
    var displayName: String { self.rawValue }
    
    var description: String {
        switch self {
        case .classic:
            return "Traditional dark theme with full controls"
        case .minimal:
            return "Clean, minimal design with essential info"
        case .fanFav:
            return "Retro-inspired design with unique styling"
        }
    }
    
    var icon: String {
        switch self {
        case .classic:
            return "music.note"
        case .minimal:
            return "circle"
        case .fanFav:
            return "star.fill"
        }
    }
}

struct ThemeConfiguration {
    let theme: AppTheme
    
    // Mini Player Configuration
    var backgroundColor: Color
    var backgroundImage: LinearGradient?
    var cornerRadius: CGFloat
    var textColor: Color
    var secondaryTextColor: Color
    var accentColor: Color
    var buttonColor: Color
    var buttonTextColor: Color
    var progressColor: Color
    var progressBgColor: Color
    var shadowRadius: CGFloat
    var font: Font
    var titleFont: Font
    var artistFont: Font
    
    // Layout Configuration
    var showAlbumArt: Bool
    var albumArtCornerRadius: CGFloat
    var compactMode: Bool
    var showControls: Bool
    var showProgressBar: Bool
    
    // Menu Configuration
    var menuBackgroundColor: Color
    var menuTextColor: Color
    var menuAccentColor: Color
    
    static func configuration(for theme: AppTheme) -> ThemeConfiguration {
        switch theme {
        case .classic:
            return ThemeConfiguration(
                theme: .classic,
                backgroundColor: Color(white: 0.15),
                backgroundImage: nil,
                cornerRadius: 34,
                textColor: .white,
                secondaryTextColor: .white.opacity(0.5),
                accentColor: .green,
                buttonColor: .clear,
                buttonTextColor: .white,
                progressColor: .green,
                progressBgColor: Color.gray.opacity(0.3),
                shadowRadius: 20,
                font: .system(size: 15),
                titleFont: .system(size: 20, weight: .bold),
                artistFont: .system(size: 15, weight: .medium),
                showAlbumArt: true,
                albumArtCornerRadius: 24,
                compactMode: false,
                showControls: true,
                showProgressBar: true,
                menuBackgroundColor: .clear,
                menuTextColor: .white,
                menuAccentColor: .green
            )

        case .minimal:
            return ThemeConfiguration(
                theme: .minimal,
                backgroundColor: Color(white: 0.15),
                backgroundImage: nil,
                cornerRadius: 34,
                textColor: .white,
                secondaryTextColor: .white.opacity(0.5),
                accentColor: .white,
                buttonColor: Color.white.opacity(0.1),
                buttonTextColor: .white,
                progressColor: .white,
                progressBgColor: Color.white.opacity(0.2),
                shadowRadius: 15,
                font: .system(size: 14),
                titleFont: .system(size: 18, weight: .semibold),
                artistFont: .system(size: 13, weight: .regular),
                showAlbumArt: true,
                albumArtCornerRadius: 28,
                compactMode: false,
                showControls: true,
                showProgressBar: true,
                menuBackgroundColor: Color(white: 0.15),
                menuTextColor: .white,
                menuAccentColor: .white
            )

        case .fanFav:
            return ThemeConfiguration(
                theme: .fanFav,
                backgroundColor: Color(red: 0.5, green: 0.55, blue: 0.5),
                backgroundImage: LinearGradient(
                    colors: [Color(red: 0.6, green: 0.65, blue: 0.6), Color(red: 0.45, green: 0.5, blue: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                cornerRadius: 28,
                textColor: Color(red: 0.9, green: 1.0, blue: 0.7),
                secondaryTextColor: Color(red: 0.9, green: 1.0, blue: 0.7).opacity(0.7),
                accentColor: Color(red: 0.9, green: 1.0, blue: 0.7),
                buttonColor: Color(red: 0.5, green: 0.55, blue: 0.5),
                buttonTextColor: Color(red: 0.1, green: 0.1, blue: 0.1),
                progressColor: Color(red: 0.9, green: 1.0, blue: 0.7),
                progressBgColor: Color(red: 0.15, green: 0.25, blue: 0.15),
                shadowRadius: 15,
                font: .custom("Courier", size: 14),
                titleFont: .custom("Courier", size: 18),
                artistFont: .custom("Courier", size: 13),
                showAlbumArt: false,
                albumArtCornerRadius: 0,
                compactMode: false,
                showControls: true,
                showProgressBar: true,
                menuBackgroundColor: Color(red: 0.2, green: 0.15, blue: 0.1),
                menuTextColor: Color(red: 0.95, green: 0.9, blue: 0.7),
                menuAccentColor: Color(red: 0.95, green: 0.9, blue: 0.7)
            )
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    // Provide a default value at declaration; AppStorage keeps it in sync with UserDefaults.
    @AppStorage("selectedTheme") private var selectedThemeRaw: String = AppTheme.classic.rawValue
    
    // Initialize directly; @Published cannot be lazy. didSet syncs to AppStorage.
    @Published var currentTheme: AppTheme = .classic {
        didSet {
            selectedThemeRaw = currentTheme.rawValue
        }
    }
    
    var currentConfiguration: ThemeConfiguration {
        ThemeConfiguration.configuration(for: currentTheme)
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
    
    private init() {
        // Seed from persisted value on init
        if let stored = AppTheme(rawValue: selectedThemeRaw) {
            self.currentTheme = stored
        } else {
            self.currentTheme = .classic
            self.selectedThemeRaw = AppTheme.classic.rawValue
        }
    }
}
