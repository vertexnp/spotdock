import SwiftUI

enum DynamicIslandSize {
    case collapsed
    case expanded
}

struct NotchShape: Shape {
    var progress: CGFloat // 0.0 (collapsed) to 1.0 (expanded)
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wingSize: CGFloat = 30 // Size of the curve coming from the top corners
        let pillHeight: CGFloat = rect.height
        let cornerRadius: CGFloat = 20 + (progress * 12)
        
        let leftEdge = wingSize
        let rightEdge = rect.width - wingSize
        
        // Start from top left corner of the screen
        path.move(to: CGPoint(x: 0, y: 0))
        
        // Left Wing - Smooth curve from corner into the island
        path.addQuadCurve(to: CGPoint(x: leftEdge, y: 22), 
                         control: CGPoint(x: leftEdge, y: 0))
        
        // Left side of the pill
        path.addLine(to: CGPoint(x: leftEdge, y: pillHeight - cornerRadius))
        path.addArc(center: CGPoint(x: leftEdge + cornerRadius, y: pillHeight - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rightEdge - cornerRadius, y: pillHeight))
        
        // Right side of the pill
        path.addArc(center: CGPoint(x: rightEdge - cornerRadius, y: pillHeight - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)
        path.addLine(to: CGPoint(x: rightEdge, y: 22))
        
        // Right Wing - Smooth curve back to the top right corner
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), 
                         control: CGPoint(x: rightEdge, y: 0))
        
        path.closeSubpath()
        return path
    }
}

struct DynamicIslandView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @ObservedObject var universalPlayer = NowPlayingManager.shared
    @Binding var size: DynamicIslandSize
    @State private var isHovering = false
    var onSizeChange: ((DynamicIslandSize) -> Void)?

    private var isUniversalActive: Bool {
        player.useUniversalNowPlaying && !universalPlayer.trackName.isEmpty && !player.isPlaying
    }

    private var currentTrackName: String { isUniversalActive ? universalPlayer.trackName : player.trackName }
    private var currentArtistName: String { isUniversalActive ? universalPlayer.artistName : player.artistName }
    private var currentIsPlaying: Bool { isUniversalActive ? universalPlayer.isPlaying : player.isPlaying }
    private var currentProgress: Double { isUniversalActive ? universalPlayer.progress : player.progress }
    private var currentDuration: Double { isUniversalActive ? universalPlayer.duration : player.duration }
    private var currentVolume: Int { isUniversalActive ? universalPlayer.systemVolume : player.volume }

    private var currentAlbumArt: some View {
        ZStack {
            if isUniversalActive {
                if let nsImage = universalPlayer.albumArt {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else { placeholderArt }
            } else {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholderArt }
            }
        }
    }

    private var placeholderArt: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "music.note").foregroundColor(.white.opacity(0.4))
        }
    }

    var body: some View {
        let isExpanded = size == .expanded
        
        ZStack(alignment: .top) {
            // 1. Background Layer - The "Winged" Notch
            ZStack {
                if isExpanded {
                    NotchShape(progress: 1.0)
                        .fill(.ultraThinMaterial)
                        .opacity(0.9)
                        .overlay(
                            NotchShape(progress: 1.0)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                } else {
                    NotchShape(progress: 0.0)
                        .fill(Color.black)
                }
            }
            .frame(width: isExpanded ? 420 : (isHovering ? 320 : 300), 
                   height: isExpanded ? 179.5 : 30)
            .shadow(color: .black.opacity(isExpanded ? 0.3 : 0.5), 
                    radius: isExpanded ? 15 : 5, 
                    y: isExpanded ? 10 : 2)
            
            // 2. Content Layer
            ZStack(alignment: .center) {
                // Collapsed content
                collapsedView
                    .frame(width: 300, height: 30)
                    .contentShape(Rectangle())
                    .opacity(isExpanded ? 0 : 1)
                    .scaleEffect(isExpanded ? 0.8 : (isHovering ? 1.05 : 1.0))
                
                // Expanded content
                expandedView
                    .frame(width: 420, height: 179.5)
                    .opacity(isExpanded ? 1 : 0)
                    .scaleEffect(isExpanded ? 1.0 : 0.9)
            }
            .frame(width: isExpanded ? 420 : 300, height: isExpanded ? 179.5 : 30)

            // 3. Interaction Area
            Color.black.opacity(0.001)
                .frame(width: isExpanded ? 420 : 320, height: isExpanded ? 60 : 30)
                .contentShape(Rectangle())
                .onTapGesture { toggleSize() }
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHovering = hovering
                    }
                }
        }
        .frame(width: isExpanded ? 420 : 320, height: isExpanded ? 179.5 : 30)
        .background(Color.clear)
        .animation(.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0), value: size)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    if abs(horizontal) > abs(vertical) {
                        if horizontal > 30 { previousTrack(); triggerHaptic() }
                        else if horizontal < -30 { nextTrack(); triggerHaptic() }
                    } else {
                        if vertical > 30 && size == .collapsed { expand() }
                        else if vertical < -30 && size == .expanded { collapse() }
                    }
                }
        )
    }

    private func togglePlay() {
        if isUniversalActive { universalPlayer.togglePlay() }
        else { Task { await player.togglePlay() } }
    }

    private func nextTrack() {
        if isUniversalActive { universalPlayer.nextTrack() }
        else { Task { await player.nextTrack() } }
    }

    private func previousTrack() {
        if isUniversalActive { universalPlayer.previousTrack() }
        else { Task { await player.previousTrack() } }
    }

    private func toggleSize() {
        if size == .collapsed { expand() }
        else { collapse() }
    }

    private func expand() {
        triggerHaptic()
        size = .expanded
        onSizeChange?(.expanded)
    }

    private func collapse() {
        triggerHaptic()
        size = .collapsed
        onSizeChange?(.collapsed)
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private var collapsedView: some View {
        HStack(spacing: 0) {
            if currentIsPlaying {
                currentAlbumArt
                    .frame(width: 24, height: 24)
                    .cornerRadius(6)
                    .padding(.leading, 38) // Original 28 + 10 padding
                Spacer()
                barsView(count: 4, height: 12).padding(.trailing, 38) // Original 28 + 10 padding
            } else {
                EyesView(scale: 0.7).padding(.leading, 38) // Original 28 + 10 padding
                Spacer()
                // Removed SleepingView as requested
            }
        }
        .padding(.horizontal, 10) // Explicit 10px padding
        .frame(height: 32)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if currentIsPlaying {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)).frame(width: 60, height: 60)
                        currentAlbumArt.frame(width: 48, height: 48).cornerRadius(6)
                    }
                } else {
                    EyesView(scale: 1.5).frame(width: 80, height: 60)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentTrackName).font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(currentArtistName).font(.system(size: 13, weight: .medium)).foregroundColor(.gray).lineLimit(1)
                }
                Spacer()
                if currentIsPlaying { barsView(count: 4, height: 14) }
            }
            .padding(.horizontal, 40).padding(.top, 24)
            Spacer(minLength: 0)
            if !isUniversalActive {
                HStack(spacing: 10) {
                    Text(formatTime(currentProgress)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                            Capsule().fill(Color.white.opacity(0.6)).frame(width: currentDuration > 0 ? geo.size.width * CGFloat(currentProgress / currentDuration) : 0, height: 4)
                        }.padding(.top, 3)
                    }.frame(height: 10)
                    Text(formatTime(currentDuration)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
                }.padding(.horizontal, 40).padding(.vertical, 8)
            }
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "headphones").font(.system(size: 14, weight: .medium))
                    Text("\(currentVolume)%").font(.system(size: 11, weight: .bold))
                }.foregroundColor(.white.opacity(0.6))
                Spacer()
                if !isUniversalActive {
                    HStack(spacing: 20) {
                        Button(action: { previousTrack() }) { Image(systemName: "backward.fill").font(.system(size: 18)).foregroundColor(.white) }.buttonStyle(.plain)
                        Button(action: { togglePlay() }) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.1)).frame(width: 42, height: 42)
                                Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                            }
                        }.buttonStyle(.plain)
                        Button(action: { nextTrack() }) { Image(systemName: "forward.fill").font(.system(size: 18)).foregroundColor(.white) }.buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "safari").font(.system(size: 12))
                        Text("Browser Playback").font(.system(size: 10, weight: .bold))
                    }.foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                if !isUniversalActive {
                    Button(action: { Task { await player.toggleShuffle() } }) { Image(systemName: "shuffle").font(.system(size: 14, weight: .bold)).foregroundColor(player.isShuffled ? .green : .white.opacity(0.6)) }.buttonStyle(.plain)
                } else { Spacer().frame(width: 14) }
            }.padding(.horizontal, 40).padding(.bottom, 20)
        }
        .frame(height: 179.5)
    }

    private func barsView(count: Int, height: CGFloat) -> some View {
        HStack(spacing: 3) { ForEach(0..<count, id: \.self) { i in bar(index: i, height: height) } }
    }

    private func bar(index: Int, height: CGFloat) -> some View {
        // Reduced frequency from 0.1s to 0.15s
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let phase = CGFloat(index) * 0.5 + CGFloat(context.date.timeIntervalSinceReferenceDate * 4)
            let barHeight = currentIsPlaying ? (height * 0.4 + sin(phase) * (height * 0.3) + (height * 0.3)) : 3
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.8, green: 0.4, blue: 0.8)).frame(width: 3, height: barHeight)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct EyesView: View {
    var scale: CGFloat = 1.0
    var body: some View {
        // Reduced frequency from 0.02s (50fps) to 0.1s (10fps) for background tracking
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let isBlinking = (Int(time) % 4 == 0) && (time.truncatingRemainder(dividingBy: 1) < 0.15)
                let spacing: CGFloat = 3 * scale
                let eyeWidth: CGFloat = 16 * scale
                let eyeHeight: CGFloat = isBlinking ? 2 * scale : 22 * scale
                let pupilSize: CGFloat = isBlinking ? 0 : 9 * scale
                let mouseLocation = NSEvent.mouseLocation
                guard let screen = NSScreen.main else { return }
                let notchX = screen.frame.midX
                let notchY = screen.frame.maxY - 16
                let dx = mouseLocation.x - notchX
                let dy = mouseLocation.y - notchY
                let dist = sqrt(dx*dx + dy*dy)
                let angle = atan2(dy, dx)
                let maxMoveX = (eyeWidth - pupilSize) / 2 - 1.0
                let maxMoveY = (eyeHeight - pupilSize) / 2 - 2.0
                let moveDist = min(dist / 500, 1.0)
                let offsetX = cos(angle) * maxMoveX * moveDist
                let offsetY = sin(angle) * maxMoveY * moveDist
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawEye(at: CGPoint(x: center.x - (eyeWidth/2 + spacing/2), y: center.y), context: &context, width: eyeWidth, height: eyeHeight, pupilSize: pupilSize, offsetX: offsetX, offsetY: offsetY, scale: scale)
                drawEye(at: CGPoint(x: center.x + (eyeWidth/2 + spacing/2), y: center.y), context: &context, width: eyeWidth, height: eyeHeight, pupilSize: pupilSize, offsetX: offsetX, offsetY: offsetY, scale: scale)
            }
        }.frame(width: 50 * scale, height: 32 * scale)
    }
    private func drawEye(at pos: CGPoint, context: inout GraphicsContext, width: CGFloat, height: CGFloat, pupilSize: CGFloat, offsetX: CGFloat, offsetY: CGFloat, scale: CGFloat) {
        let scleraRect = CGRect(x: pos.x - width/2, y: pos.y - height/2, width: width, height: height)
        context.fill(Path(ellipseIn: scleraRect), with: .color(.white))
        if pupilSize > 0 {
            let pupilX = pos.x + offsetX - pupilSize/2
            let pupilY = pos.y - offsetY - pupilSize/2
            let pupilRect = CGRect(x: pupilX, y: pupilY, width: pupilSize, height: pupilSize)
            context.fill(Path(ellipseIn: pupilRect), with: .color(Color(white: 0.1)))
            let gleamSize = pupilSize * 0.35
            let gleamRect = CGRect(x: pupilX + pupilSize * 0.45, y: pupilY + pupilSize * 0.15, width: gleamSize, height: gleamSize)
            context.fill(Path(ellipseIn: gleamRect), with: .color(.white))
        }
    }
}
