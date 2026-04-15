<p align="center">
  <img src="assets/logo.png" width="128" height="128" alt="SpotDock Logo" style="background-color: white; border-radius: 25px; padding: 10px;">
</p>

# SpotDock

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform: macOS">
  <img src="https://img.shields.io/badge/language-Swift-orange.svg" alt="Language: Swift">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
</p>

SpotDock is a lightweight macOS menu bar application that provides a beautiful and functional mini player for Spotify. It allows you to control your music playback and view track information directly from your menu bar without interrupting your workflow.

## Features

- Menu Bar Integration: Access your music controls quickly from the macOS menu bar.
- Playback Control: Play, pause, skip tracks, and toggle shuffle or repeat modes.
- Track Information: View the current song title, artist name, and album artwork.
- Multiple Themes: Choose from various visual styles to match your desktop aesthetic.
- Progress Tracking: Real-time progress bar for the currently playing track.
- Recently Played: Quickly view and access your recently played tracks in supported themes.
- Interactive Visuals: Animated components like vinyl records and audio waveforms.

## API Integration

SpotDock interacts with the following Spotify and external API endpoints. Below is a breakdown of what to expect from each request.

### Spotify Accounts API

- **POST https://accounts.spotify.com/api/token**
  - Use: Exchanging authorization codes or refreshing tokens.
  - Expect: A JSON object containing `access_token`, `token_type`, `expires_in`, and optionally `refresh_token`.

- **GET https://accounts.spotify.com/authorize**
  - Use: User authentication.
  - Expect: A redirect to the specified callback URI with a `code` parameter.

### Spotify Player API

- **GET https://api.spotify.com/v1/me/player**
  - Use: Fetching current playback state.
  - Expect: 
    - `item`: Object containing track `id`, `name`, `artists` array, `album` (with `images`), and `duration_ms`.
    - `progress_ms`: Current playback position.
    - `is_playing`: Boolean status of playback.
    - `shuffle_state` and `repeat_state`: Current playback modes.
    - `device`: Object with `name` and `volume_percent`.

- **PUT https://api.spotify.com/v1/me/player/play**
  - Use: Resume or start playback.
  - Expect: 204 No Content on success.

- **PUT https://api.spotify.com/v1/me/player/pause**
  - Use: Pause playback.
  - Expect: 204 No Content on success.

- **POST https://api.spotify.com/v1/me/player/next**
  - Use: Skip to next track.
  - Expect: 204 No Content on success.

- **POST https://api.spotify.com/v1/me/player/previous**
  - Use: Skip to previous track.
  - Expect: 204 No Content on success.

- **PUT https://api.spotify.com/v1/me/player/volume**
  - Use: Set playback volume.
  - Expect: 204 No Content on success.

- **PUT https://api.spotify.com/v1/me/player/shuffle**
  - Use: Toggle shuffle.
  - Expect: 204 No Content on success.

- **PUT https://api.spotify.com/v1/me/player/repeat**
  - Use: Cycle repeat mode.
  - Expect: 204 No Content on success.

- **GET https://api.spotify.com/v1/me/player/recently-played**
  - Use: Get recently played tracks.
  - Expect: An object with an `items` array, where each entry contains a `track` object with `id`, `name`, `artists`, and `album.images`.

### Lyrics API

- **GET https://lrclib.net/api/get**
  - Use: Fetching lyrics by artist and track name.
  - Expect: A JSON object containing `plainLyrics` (string) and `syncedLyrics` (LRC format string).

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
