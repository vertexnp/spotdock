//
//  MiniPlayerView.swift
//  Spotify
//

import SwiftUI

enum ViewMode {
    case player
    case lyrics
}

struct MiniPlayerView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @State private var localVolume: Double = 50

    private let themeManager = ThemeManager.shared

    // macOS 15 Widget Style Corner Radius
    private var themeConfiguration: ThemeConfiguration {
        ThemeConfiguration.configuration(for: themeManager.currentTheme)
    }
    
    var body: some View {
        ZStack {
            // Background based on theme
            if themeManager.currentTheme == .fanFav {
                fanFavBackgroundActual
            } else {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(themeConfiguration.backgroundColor)
            }

            // Content
            Group {
                if !player.showLyrics {
                    playerModeView
                } else {
                    lyricsModeView
                }
            }
            
            // Error overlay for rate limit and other errors
            if player.error != nil {
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
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(width: 440, height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onAppear {
            localVolume = Double(player.volume)
        }
        .onChange(of: player.volume) { oldValue, newValue in
            localVolume = Double(newValue)
        }
    }

    private var fanFavBackgroundActual: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.08, green: 0.1, blue: 0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var playerModeView: some View {
        Group {
            if themeManager.currentTheme == .fanFav {
                fanFavPlayerModeView
                    .padding(35)
            } else if themeManager.currentTheme == .minimal {
                minimalPlayerModeView
            } else {
                // Classic - no extra padding, layout fills container
                defaultPlayerModeView
            }
        }
    }

    private var minimalPlayerModeView: some View {
        HStack(spacing: 20) {
            // Left section - Album art, track info, progress
            VStack(alignment: .leading, spacing: 0) {
                // Album art
                albumArt(size: 80)
                    .padding(.bottom, 12)
                
                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                    
                    Text(player.trackName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.bottom, 16)
                
                // Progress bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(.white)
                                .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 4)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 4)
                    
                    HStack {
                        Text(formatTime(player.progress))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(player.duration))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right section - 2x2 grid: lyrics, play/pause, next, prev
            VStack(spacing: 12) {
                // Top row - Lyrics toggle, Play/Pause
                HStack(spacing: 12) {
                    // Lyrics toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            player.showLyrics = true
                        }
                    }) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    // Play/Pause
                    Button(action: { Task { await player.togglePlay() } }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                
                // Bottom row - Prev, Next
                HStack(spacing: 12) {
                    Button(action: { Task { await player.previousTrack() } }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { Task { await player.nextTrack() } }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
    }

    // Vinyl rotation angle based on playback progress
    private var vinylRotation: Double {
        guard player.duration > 0 else { return 0 }
        return (player.progress / player.duration) * 360
    }

    // Tone arm angle: rest position when paused, moves over record when playing
    private var toneArmAngle: Double {
        player.isPlaying ? 18 : -8
    }

    private var fanFavPlayerModeView: some View {
        VStack(spacing: 0) {
            // Row 1: Timer | Vinyl | Lyrics toggle
            topRow

            Spacer()

            // Row 2: Controls (centered)
            HStack {
                Spacer()
                controlsButtons
                Spacer()
            }
            .padding(.bottom, 16)

            // Row 3: Song name + Artist (centered)
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text(player.trackName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(player.artistName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                player.showLyrics.toggle()
            }
        }
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            // Timer (left)
            VStack(alignment: .leading, spacing: 1) {
                Text(formatTime(player.progress))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("-" + formatTime(max(0, player.duration - player.progress)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .monospacedDigit()
            }
            .frame(width: 44, alignment: .leading)

            Spacer()

            // Vinyl (center)
            vinylRecordSection

            Spacer()

            // Lyrics toggle (right)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    player.showLyrics.toggle()
                }
            }) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(white: 0.08)))
            }
            .buttonStyle(.plain)
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    private var vinylRecordSection: some View {
        ZStack {
            vinylDisc
            toneArmView
        }
        .frame(width: 100, height: 100)
    }

    private var vinylDisc: some View {
        ZStack {
            vinylBase
            vinylGrooves
            vinylHighlight
            vinylCenter
        }
        .rotationEffect(.degrees(vinylRotation))
    }

    private var vinylBase: some View {
        Circle()
            .fill(Color(white: 0.06))
            .frame(width: 140, height: 140)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
    }

    private var vinylGrooves: some View {
        Group {
            groove(at: 0)
            groove(at: 1)
            groove(at: 2)
            groove(at: 3)
            groove(at: 4)
            groove(at: 5)
            groove(at: 6)
            groove(at: 7)
            groove(at: 8)
            groove(at: 9)
            groove(at: 10)
            groove(at: 11)
        }
    }

    private func groove(at index: Int) -> some View {
        let size = CGFloat(40 + index) * 7.5
        return Circle()
            .stroke(Color(white: 0.03).opacity(0.3), lineWidth: 0.5)
            .frame(width: size, height: size)
    }

    private var vinylHighlight: some View {
        Circle()
            .trim(from: 0.08, to: 0.28)
            .stroke(Color.white.opacity(0.04), lineWidth: 12)
            .frame(width: 140, height: 140)
    }

    private var vinylCenter: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.08))
                .frame(width: 52, height: 52)

            albumArtCircle

            Circle()
                .fill(Color(white: 0.03))
                .frame(width: 4, height: 4)
        }
    }

    private var albumArtCircle: some View {
        AsyncImage(url: URL(string: player.albumArtURL)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle()
                .fill(Color(white: 0.1))
                .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(.gray.opacity(0.3)))
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
    }

    private var controlsButtons: some View {
        HStack(spacing: 10) {
            controlButton(icon: "backward.fill", size: 13) { await player.previousTrack() }
            controlButton(icon: player.isPlaying ? "pause.fill" : "play.fill", size: 16) { await player.togglePlay() }
            controlButton(icon: "forward.fill", size: 13) { await player.nextTrack() }
        }
    }

    private func controlButton(icon: String, size: CGFloat, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(white: 0.1)))
        }
        .buttonStyle(.plain)
    }

    // Tone arm component
    private var toneArmView: some View {
        Group {
            // Pivot base (top right)
            Circle()
                .fill(Color(white: 0.1))
                .frame(width: 10, height: 10)
                .offset(x: 52, y: -58)
            
            // Arm shaft
            Path { path in
                let pivotX: CGFloat = 52
                let pivotY: CGFloat = -58
                let armLength: CGFloat = 70
                let angle = toneArmAngle
                
                let endX = pivotX + armLength * cos(angle * .pi / 180)
                let endY = pivotY + armLength * sin(angle * .pi / 180)
                
                path.move(to: CGPoint(x: pivotX, y: pivotY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(Color(white: 0.14), lineWidth: 3)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 1)
            
            // Headshell
            let angle = toneArmAngle
            let armLength: CGFloat = 70
            let headX: CGFloat = 52 + armLength * cos(angle * .pi / 180)
            let headY: CGFloat = -58 + armLength * sin(angle * .pi / 180)
            
            Rectangle()
                .fill(Color(white: 0.1))
                .frame(width: 6, height: 4)
                .position(x: headX, y: headY)
                .cornerRadius(1)
        }
    }

    private var defaultPlayerModeView: some View {
        HStack(spacing: 0) {
            // LEFT SIDE: 60% - Full-height album art
            AsyncImage(url: URL(string: player.albumArtURL)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.3)
                    .overlay(Image(systemName: "music.note").font(.system(size: 40)).foregroundColor(.gray))
            }
            .frame(maxWidth: .infinity * 0.67, maxHeight: .infinity) // 40% left
            .clipped()
            
            // RIGHT SIDE: 60% - Content area
            VStack(alignment: .leading, spacing: 0) {
                // Row 1: Song name | Lyrics toggle
                HStack {
                    Text(player.trackName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            player.showLyrics.toggle()
                        }
                    }) {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Row 2: Artist name
                Text(player.artistName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                
                // Row 3: 20px space
                Spacer(minLength: 20)
                
                // Row 4: Timestamp + Progress bar
                HStack(spacing: 8) {
                    Text(formatTime(player.progress))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 3)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(formatTime(player.duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                }
                .frame(height: 14)
                .padding(.horizontal, 16)
                
                // Row 5: Controls
                HStack(spacing: 20) {
                    Spacer()
                    
                    Button(action: { Task { await player.previousTrack() } }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { Task { await player.togglePlay() } }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { Task { await player.nextTrack() } }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 60% right
        }
        .frame(width: 440, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(nsColor: NSColor.windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var lyricsModeView: some View {
        Group {
            if themeManager.currentTheme == .fanFav {
                fanFavLyricsModeView
                    .padding(35)
            } else {
                defaultLyricsModeView
                    .padding(35)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                player.showLyrics = false
            }
        }
    }

    private var fanFavLyricsModeView: some View {
        VStack(spacing: 0) {
            // Mini vinyl on top
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(white: 0.08), Color(white: 0.14), Color(white: 0.08),
                                Color(white: 0.11), Color(white: 0.08), Color(white: 0.13)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 80, height: 80)
                
                // Album art center
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color(white: 0.15))
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                
                // Center hole
                Circle().fill(Color(white: 0.05)).frame(width: 5, height: 5)
            }
            .frame(height: 100)
            
            // Lyrics area
            VStack(spacing: 0) {
                // Time bar
                HStack {
                    Text(formatTime(player.progress))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 3)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 3)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(formatTime(player.duration))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(height: 16)
                .padding(.horizontal, 24)
                
                // Lyrics scroll
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        if !player.syncedLyrics.isEmpty {
                            VStack(spacing: 14) {
                                ForEach(Array(player.syncedLyrics.enumerated()), id: \.element.id) { index, line in
                                    Text(line.text)
                                        .font(.system(size: index == currentLyricIndex ? 18 : 14, weight: index == currentLyricIndex ? .semibold : .regular))
                                        .foregroundColor(index == currentLyricIndex ? .white : .white.opacity(0.35))
                                        .id(line.id)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 12)
                            .onChange(of: player.progress) { _, newValue in
                                if let currentLine = player.syncedLyrics.last(where: { $0.timestamp <= newValue }) {
                                    withAnimation(.smooth) {
                                        proxy.scrollTo(currentLine.id, anchor: .center)
                                    }
                                }
                            }
                        } else {
                            VStack {
                                Spacer()
                                Text("Lyrics not available")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.4))
                                Spacer()
                            }
                            .frame(height: 60)
                        }
                    }
                    .frame(height: 90)
                }
            }
            
            // Bottom controls
            HStack {
                Button(action: { Task { await player.previousTrack() } }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(white: 0.08)))
                }
                .buttonStyle(.plain)
                
                Button(action: { Task { await player.togglePlay() } }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(white: 0.08)).shadow(color: .black.opacity(0.3), radius: 4, y: 2))
                }
                .buttonStyle(.plain)
                
                Button(action: { Task { await player.nextTrack() } }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(white: 0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
    }

    private var currentLyricIndex: Int {
        player.syncedLyrics.lastIndex(where: { $0.timestamp <= player.progress }) ?? 0
    }

    private var defaultLyricsModeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with album art, track info, and mic icon
            HStack(spacing: 14) {
                // Album art
                albumArt(size: 56)
                
                // Track info
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.trackName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(player.artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()
                
                // Lyrics icon - tap to go back
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        player.showLyrics = false
                    }
                }) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            // Lyrics content - tap anywhere to go back
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    if !player.syncedLyrics.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(player.syncedLyrics) { line in
                                Text(line.text)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(isCurrentLine(line) ? .white : .white.opacity(0.3))
                                    .scaleEffect(isCurrentLine(line) ? 1.02 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCurrentLine(line))
                                    .id(line.id)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 200)
                        .onChange(of: player.progress) { _, newValue in
                            if let currentLine = player.syncedLyrics.last(where: { $0.timestamp <= newValue }) {
                                withAnimation(.smooth) {
                                    proxy.scrollTo(currentLine.id, anchor: .center)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .center) {
                            Spacer()
                            Text("Lyrics for this music is not found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                            Spacer()
                        }
                        .frame(height: 200)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                player.showLyrics = false
            }
        }
    }

    private func albumArt(size: CGFloat) -> some View {
        ZStack {
            if !player.albumArtURL.isEmpty {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .cornerRadius(themeConfiguration.albumArtCornerRadius)
                } placeholder: {
                    placeholderArt(size: size * 0.3)
                }
            } else {
                placeholderArt(size: size * 0.3)
            }
        }
        .frame(width: size, height: size)
    }

    private var expandButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                player.showLyrics.toggle()
            }
        }) {
            Image(systemName: !player.showLyrics ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(themeConfiguration.secondaryTextColor)
                .padding(8)
                .background(themeConfiguration.buttonColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func placeholderArt(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: themeConfiguration.albumArtCornerRadius)
            .fill(Color.white.opacity(0.05))
            .overlay(Image(systemName: "music.note").font(.system(size: size)).foregroundColor(Color.white.opacity(0.1)))
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func isCurrentLine(_ line: LyricLine) -> Bool {
        guard let currentIndex = player.syncedLyrics.firstIndex(where: { $0.id == line.id }) else { return false }
        let nextLine = currentIndex + 1 < player.syncedLyrics.count ? player.syncedLyrics[currentIndex + 1] : nil
        return player.progress >= line.timestamp && (nextLine == nil || player.progress < nextLine!.timestamp)
    }

    private func cleanLyrics(_ lyrics: String) -> String {
        let pattern = "\\[\\d{2}:\\d{2}\\.\\d{2,3}\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: lyrics.utf16.count)
        return regex?.stringByReplacingMatches(in: lyrics, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? lyrics
    }
}

struct ThemedButtonStyle: ButtonStyle {
    let configuration: ThemeConfiguration

    func makeBody(configuration buttonConfig: Configuration) -> some View {
        buttonConfig.label
            .foregroundColor(self.configuration.textColor)
            .scaleEffect(buttonConfig.isPressed ? 0.9 : 1.0)
            .opacity(buttonConfig.isPressed ? 0.7 : 1.0)
    }
}

struct ButtonScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
