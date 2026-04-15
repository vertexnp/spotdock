# SpotDock

SpotDock is a lightweight macOS menu bar application that provides a beautiful and functional mini player for Spotify. It allows you to control your music playback and view track information directly from your menu bar without interrupting your workflow.

<img src="assets/logo.png" width="128" height="128" alt="SpotDock Logo">

## Features

- Menu Bar Integration: Access your music controls quickly from the macOS menu bar.
- Playback Control: Play, pause, skip tracks, and toggle shuffle or repeat modes.
- Track Information: View the current song title, artist name, and album artwork.
- Multiple Themes: Choose from various visual styles to match your desktop aesthetic.
- Progress Tracking: Real-time progress bar for the currently playing track.
- Recently Played: Quickly view and access your recently played tracks in supported themes.
- Interactive Visuals: Animated components like vinyl records and audio waveforms.

## Themes

### Classic
A focused view featuring high-quality album artwork with overlay controls that appear on hover. It provides a clean, image-centric experience.

### Minimal
A compact design that displays essential track information alongside a dynamic audio waveform visualizer. Ideal for users who prefer a subtle presence.

### FanFav
An immersive experience featuring an animated vinyl record that rotates during playback, along with a horizontal list of recently played tracks.

## Installation

1. Clone the repository to your local machine.
2. Open `spotifywidget.xcodeproj` in Xcode.
3. Ensure you have the necessary development certificates and team settings configured in Xcode.
4. Build and run the project (Cmd + R).

## Usage

1. Launch SpotDock.
2. Click the music icon in your menu bar.
3. Click the Login button to authenticate with your Spotify account.
4. Once authenticated, the mini player will display your current playback.
5. Use the gear icon to access settings and switch between themes.

## Requirements

- macOS 12.0 or later
- A Spotify account (Spotify Premium recommended for full control functionality)
- Xcode 14.0 or later (for building from source)

## Configuration

The application uses Spotify's Web API. For your own builds, you may need to configure your own Spotify Client ID and Client Secret in the environment settings if the default ones are not provided or expired.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

<img src="assets/Spotify app icon white on black.jpeg" width="64" height="64" alt="Spotify Icon">
