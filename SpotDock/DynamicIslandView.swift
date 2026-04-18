import SwiftUI

enum DynamicIslandSize {
    case collapsed
    case expanded
}

struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wingSize: CGFloat = 20
        let pillWidth: CGFloat = rect.width - (wingSize * 2)
        let pillHeight: CGFloat = rect.height
        
        let cornerRadius: CGFloat = (pillHeight < 50) ? 8 : 12
        
        let leftEdge = wingSize
        let rightEdge = rect.width - wingSize
        
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: leftEdge, y: wingSize), control: CGPoint(x: leftEdge, y: 0))
        path.addLine(to: CGPoint(x: leftEdge, y: pillHeight - cornerRadius))
        path.addArc(center: CGPoint(x: leftEdge + cornerRadius, y: pillHeight - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)
        path.addLine(to: CGPoint(x: rightEdge - cornerRadius, y: pillHeight))
        path.addArc(center: CGPoint(x: rightEdge - cornerRadius, y: pillHeight - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)
        path.addLine(to: CGPoint(x: rightEdge, y: wingSize))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rightEdge, y: 0))
        
        path.closeSubpath()
        return path
    }
}

struct DynamicIslandView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @Binding var size: DynamicIslandSize
    @State private var isHovering = false
    var onSizeChange: ((DynamicIslandSize) -> Void)?

    private let animationDuration: Double = 0.3

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Background Shape
            NotchShape()
                .fill(Color.black)
                .frame(height: size == .collapsed ? 30.5 : 179.5)
            
            // 2. Content Container - Stable hierarchy for smoother transitions
            ZStack(alignment: .top) {
                collapsedView
                    .frame(maxWidth: .infinity)
                    .frame(height: 30.5)
                    .opacity(size == .collapsed ? 1 : 0)
                    .scaleEffect(size == .collapsed ? 1.0 : 0.9)
                    .blur(radius: size == .collapsed ? 0 : 4)
                
                expandedView
                    .frame(maxWidth: .infinity)
                    .frame(height: 179.5)
                    .opacity(size == .expanded ? 1 : 0)
                    .scaleEffect(size == .expanded ? 1.0 : 1.1)
                    .blur(radius: size == .expanded ? 0 : 10)
            }
            .padding(.horizontal, 20)
            .frame(width: size == .collapsed ? 240 : 420, height: size == .collapsed ? 30.5 : 179.5, alignment: .top)
            .clipped()

            // 3. Invisible Toggle Area
            Rectangle()
                .fill(Color.black.opacity(0.001))
                .frame(width: size == .collapsed ? 240 : 420, height: size == .collapsed ? 30.5 : 60)
                .onTapGesture {
                    toggleSize()
                }
        }
        .frame(width: size == .collapsed ? 240 : 420, height: size == .collapsed ? 30.5 : 179.5)
        .ignoresSafeArea()
        .contentShape(Rectangle()) 
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    
                    if abs(horizontal) > abs(vertical) {
                        if horizontal > 30 {
                            Task { await player.previousTrack() }
                            triggerHaptic()
                        } else if horizontal < -30 {
                            Task { await player.nextTrack() }
                            triggerHaptic()
                        }
                    } else {
                        if vertical > 30 && size == .collapsed {
                            expand()
                        } else if vertical < -30 && size == .expanded {
                            collapse()
                        }
                    }
                }
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if size == .expanded {
                collapse()
            }
        }
    }

    private func toggleSize() {
        if size == .collapsed {
            expand()
        } else {
            collapse()
        }
    }

    private func expand() {
        triggerHaptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            size = .expanded
        }
        onSizeChange?(.expanded)
    }

    private func collapse() {
        triggerHaptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            size = .collapsed
        }
        onSizeChange?(.collapsed)
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private var collapsedView: some View {
        HStack(spacing: 0) {
            if player.isPlaying {
                AsyncImage(url: URL(string: player.albumArtURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 24, height: 24)
                .cornerRadius(6)
                .padding(.leading, 45)
            
                Spacer()
                barsView(count: 4, height: 12).padding(.trailing, 45)
            } else {
                // Not playing - Move items further in to avoid wings and camera
                EyesView(scale: 0.7)
                    .padding(.leading, 45)
                
                Spacer() // Space for the camera
                
                SleepingView()
                    .padding(.trailing, 45)
            }
        }
        .frame(height: 30.5)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if player.isPlaying {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)).frame(width: 60, height: 60)
                        AsyncImage(url: URL(string: player.albumArtURL)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)
                    }
                } else {
                    EyesView(scale: 1.5)
                        .frame(width: 80, height: 60)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.trackName).font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(player.artistName).font(.system(size: 13, weight: .medium)).foregroundColor(.gray).lineLimit(1)
                }
                Spacer()
                if player.isPlaying {
                    barsView(count: 4, height: 14)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text(formatTime(player.progress)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                        Capsule().fill(Color.white.opacity(0.6)).frame(width: player.duration > 0 ? geo.size.width * CGFloat(player.progress / player.duration) : 0, height: 4)
                    }.padding(.top, 3)
                }.frame(height: 10)
                Text(formatTime(player.duration)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
            }.padding(.horizontal, 20).padding(.vertical, 8)
            HStack {
                // Volume / Headphones
                HStack(spacing: 4) {
                    Image(systemName: "headphones")
                        .font(.system(size: 14, weight: .medium))
                    Text("\(player.volume)%")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                HStack(spacing: 20) {
                    Button(action: { Task { await player.previousTrack() } }) { Image(systemName: "backward.fill").font(.system(size: 18)).foregroundColor(.white) }.buttonStyle(.plain)
                    Button(action: { Task { await player.togglePlay() } }) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.1)).frame(width: 42, height: 42)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                        }
                    }.buttonStyle(.plain)
                    Button(action: { Task { await player.nextTrack() } }) { Image(systemName: "forward.fill").font(.system(size: 18)).foregroundColor(.white) }.buttonStyle(.plain)
                }
                Spacer()
                Button(action: { Task { await player.toggleShuffle() } }) { Image(systemName: "shuffle").font(.system(size: 14, weight: .bold)).foregroundColor(player.isShuffled ? .green : .white.opacity(0.6)) }.buttonStyle(.plain)
            }.padding(.horizontal, 30).padding(.bottom, 20)
        }
        .frame(height: 179.5)
    }

    private func barsView(count: Int, height: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                bar(index: i, height: height)
            }
        }
    }

    private func bar(index: Int, height: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let phase = CGFloat(index) * 0.5 + CGFloat(context.date.timeIntervalSinceReferenceDate * 5)
            let barHeight = player.isPlaying ? (height * 0.4 + sin(phase) * (height * 0.3) + (height * 0.3)) : 3
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.8, green: 0.4, blue: 0.8)).frame(width: 3, height: barHeight)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct SleepingView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3) { i in
                    let relativeTime = time * 1.5 - Double(i) * 0.6
                    let phase = relativeTime.truncatingRemainder(dividingBy: 3.0)
                    
                    // Drifting animation: Fade in, move up, fade out
                    let opacity = phase < 1.0 ? phase : (phase < 2.0 ? 1.0 - (phase - 1.0) : 0.0)
                    let offset = -phase * 6
                    
                    Text(i == 0 ? "z" : (i == 1 ? "Z" : "Z"))
                        .font(.system(size: CGFloat(10 + i * 2), weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(opacity * 0.6))
                        .offset(y: offset)
                }
            }
        }
    }
}

struct EyesView: View {
    var scale: CGFloat = 1.0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.02)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let isBlinking = (Int(time) % 4 == 0) && (time.truncatingRemainder(dividingBy: 1) < 0.15)
                
                // 👀 Emoji proportions: Tall ovals, very close together
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

                // Center Point for both eyes together
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // Left Eye
                drawEye(at: CGPoint(x: center.x - (eyeWidth/2 + spacing/2), y: center.y), 
                        context: &context, width: eyeWidth, height: eyeHeight, pupilSize: pupilSize, 
                        offsetX: offsetX, offsetY: offsetY, scale: scale)
                
                // Right Eye
                drawEye(at: CGPoint(x: center.x + (eyeWidth/2 + spacing/2), y: center.y), 
                        context: &context, width: eyeWidth, height: eyeHeight, pupilSize: pupilSize, 
                        offsetX: offsetX, offsetY: offsetY, scale: scale)
            }
        }
        .frame(width: 50 * scale, height: 32 * scale)
    }
    
    private func drawEye(at pos: CGPoint, context: inout GraphicsContext, width: CGFloat, height: CGFloat, pupilSize: CGFloat, offsetX: CGFloat, offsetY: CGFloat, scale: CGFloat) {
        let scleraRect = CGRect(x: pos.x - width/2, y: pos.y - height/2, width: width, height: height)
        let scleraPath = Path(ellipseIn: scleraRect)
        
        // Sclera (White part)
        context.fill(scleraPath, with: .color(.white))
        
        if pupilSize > 0 {
            let pupilX = pos.x + offsetX - pupilSize/2
            let pupilY = pos.y - offsetY - pupilSize/2
            let pupilRect = CGRect(x: pupilX, y: pupilY, width: pupilSize, height: pupilSize)
            
            // Pupil (Black part)
            context.fill(Path(ellipseIn: pupilRect), with: .color(Color(white: 0.1)))
            
            // Catchlight / Gleam (White reflection dot inside the pupil)
            let gleamSize = pupilSize * 0.35
            let gleamRect = CGRect(
                x: pupilX + pupilSize * 0.45,
                y: pupilY + pupilSize * 0.15,
                width: gleamSize,
                height: gleamSize
            )
            context.fill(Path(ellipseIn: gleamRect), with: .color(.white))
        }
    }
}
