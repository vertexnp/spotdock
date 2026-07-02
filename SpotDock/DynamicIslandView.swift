import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum DynamicIslandSize {
    case collapsed
    case expanded
}

enum FileOperation {
    case compress
    case convert
}

struct NotchShape: Shape {
    var progress: CGFloat // 0.0 (collapsed) to 1.0 (expanded)
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wingSize: CGFloat = 30 
        
        // Interpolate values based on progress for a smooth morph
        let cornerRadius: CGFloat = 12 + (progress * 10) // 12 -> 22
        let wingDepth: CGFloat = 18 + (progress * 6)    // 18 -> 24
        
        let leftEdge = wingSize
        let rightEdge = rect.width - wingSize
        
        // Start ABOVE the rect (y: -100) to ensure it never "detaches" from top
        path.move(to: CGPoint(x: 0, y: -100))
        path.addLine(to: CGPoint(x: 0, y: 0))
        
        // Curve from bezel edge to pill top-left
        path.addQuadCurve(to: CGPoint(x: leftEdge, y: wingDepth), 
                         control: CGPoint(x: leftEdge, y: 0))
        
        // Left side down
        path.addLine(to: CGPoint(x: leftEdge, y: rect.height - cornerRadius))
        
        // Bottom left corner
        path.addArc(center: CGPoint(x: leftEdge + cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rightEdge - cornerRadius, y: rect.height))
        
        // Bottom right corner
        path.addArc(center: CGPoint(x: rightEdge - cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)
        
        // Right side up
        path.addLine(to: CGPoint(x: rightEdge, y: wingDepth))
        
        // Curve from pill top-right back to bezel edge
        path.addQuadCurve(to: CGPoint(x: rect.width, y: 0), 
                         control: CGPoint(x: rightEdge, y: 0))
        
        path.addLine(to: CGPoint(x: rect.width, y: -100))
        path.closeSubpath()
        return path
    }
}

struct DynamicIslandView: View {
    @ObservedObject var player = SpotifyPlayer.shared
    @ObservedObject var universalPlayer = NowPlayingManager.shared
    @Binding var size: DynamicIslandSize
    @State private var isHovering = false
    @Namespace private var animation
    var onSizeChange: ((DynamicIslandSize) -> Void)?

    // File Operation States
    @State private var droppedFileURL: URL? = nil
    @State private var isProcessing = false
    @State private var processSuccess = false
    @State private var errorMessage: String? = nil
    @State private var processedFileURL: URL? = nil
    @State private var selectedOperation: FileOperation = .compress
    @State private var selectedExtension: String = "mp4"
    @State private var compressionQuality: Double = 80.0
    @State private var isTargetedDrop = false
    @Namespace private var tabAnimation

    private var isUniversalActive: Bool {
        // Priority: Only use universal/browser if Spotify is NOT playing and browser IS playing
        player.useUniversalNowPlaying && !player.isPlaying && universalPlayer.isPlaying && !universalPlayer.trackName.isEmpty
    }

    private var hasActivePlayback: Bool {
        player.isPlaying || (universalPlayer.isPlaying && !universalPlayer.trackName.isEmpty)
    }

    private var currentTrackName: String { isUniversalActive ? universalPlayer.trackName : player.trackName }
    private var currentArtistName: String { isUniversalActive ? universalPlayer.artistName : player.artistName }
    private var currentIsPlaying: Bool { 
        player.isPlaying || (player.useUniversalNowPlaying && universalPlayer.isPlaying)
    }
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
            // 1. Background Layer - Precise 2-stage animation
            NotchShape(progress: isExpanded ? 1.0 : 0.0)
                .fill(Color.black)
                .overlay(
                    NotchShape(progress: isExpanded ? 1.0 : 0.0)
                        .stroke(Color.white.opacity(isExpanded ? 0.05 : 0), lineWidth: 0.5)
                )
                .contentShape(NotchShape(progress: isExpanded ? 1.0 : 0.0))
                .onTapGesture { toggleSize() }
                // Shape Morph & Height: immediate
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
                
                .frame(
                    width: isExpanded ? 420 : (isHovering ? 320 : 300),
                    height: isExpanded ? 160 : 30
                )
                .shadow(color: .black.opacity(0.5), 
                        radius: isExpanded ? 10 : 5, 
                        y: isExpanded ? 5 : 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isHovering)
        
        // 2. Content Layer
        ZStack {
            if isExpanded {
                if isTargetedDrop {
                    dropZoneView
                        .transition(.opacity)
                } else if droppedFileURL != nil {
                    fileOperationView
                        .transition(.opacity)
                } else {
                    expandedView
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.15).delay(0.1)),
                            removal: .opacity.animation(.easeInOut(duration: 0.1))
                        ))
                }
            } else {
                collapsedView
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.15).delay(0.05)),
                        removal: .opacity.animation(.easeInOut(duration: 0.1))
                    ))
            }
        }
        .frame(width: isExpanded ? 360 : 320, height: isExpanded ? 160 : 30)

        // 3. Interaction Area
        Color.black.opacity(0.001)
            .frame(width: isExpanded ? 360 : 320, height: isExpanded ? 160 : 30)
            .contentShape(Rectangle())
            .onTapGesture { 
                if !isExpanded {
                    toggleSize() 
                }
            }
            .allowsHitTesting(!isExpanded)
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovering = hovering
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) // Fill fixed window, pin to top
        .background(Color.clear)
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    
                    if size == .collapsed {
                        if abs(horizontal) > abs(vertical) {
                            if horizontal > 30 { previousTrack(); triggerHaptic() }
                            else if horizontal < -30 { nextTrack(); triggerHaptic() }
                        } else {
                            if vertical > 30 { expand() }
                        }
                    } else {
                        // In expanded state, dragging files or sliders should never alter track playback
                        if abs(horizontal) <= abs(vertical) && vertical < -30 {
                            collapse()
                        }
                    }
                }
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargetedDrop) { providers in
            handleDroppedFile(providers: providers)
        }
        .onChange(of: isTargetedDrop) { _, isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.size = .expanded
                    self.onSizeChange?(.expanded)
                }
            } else if droppedFileURL == nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.size = .collapsed
                    self.onSizeChange?(.collapsed)
                }
            }
        }
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
        ZStack {
            if droppedFileURL != nil {
                HStack {
                    Image(systemName: isDroppedFileVideo ? "video.badge.plus" : "photo.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .padding(.leading, 35)
                    Spacer()
                    Text("File Action")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.trailing, 35)
                }
            } else if hasActivePlayback {
                HStack(spacing: 0) {
                    currentAlbumArt
                        .matchedGeometryEffect(id: "albumArt", in: animation)
                        .frame(width: 24, height: 24)
                        .cornerRadius(6)
                    Spacer()
                    barsView(count: 4, height: 12)
                        .matchedGeometryEffect(id: "visualizer", in: animation)
                }
                .padding(.horizontal, 35)
            } else {
                HStack {
                    EyesView(scale: 0.7)
                        .padding(.leading, 35)
                    Spacer()
                }
            }
        }
        .frame(width: isHovering ? 320 : 300, height: 30)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if hasActivePlayback {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)).frame(width: 60, height: 60)
                        currentAlbumArt
                            .matchedGeometryEffect(id: "albumArt", in: animation)
                            .frame(width: 48, height: 48).cornerRadius(6)
                    }
                } else {
                    EyesView(scale: 1.5).frame(width: 80, height: 60)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasActivePlayback ? currentTrackName : "Ready to Play").font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(hasActivePlayback ? currentArtistName : "Spotify or YouTube").font(.system(size: 13, weight: .medium)).foregroundColor(.gray).lineLimit(1)
                }
                Spacer()
                if hasActivePlayback {
                    barsView(count: 4, height: 14)
                        .matchedGeometryEffect(id: "visualizer", in: animation)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24)
            
            Spacer(minLength: 0)
            
            if hasActivePlayback && !isUniversalActive {
                HStack(spacing: 10) {
                    Text(formatTime(currentProgress)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                            Capsule().fill(Color.white.opacity(0.6)).frame(width: currentDuration > 0 ? geo.size.width * CGFloat(currentProgress / currentDuration) : 0, height: 4)
                        }.padding(.top, 3)
                    }.frame(height: 10)
                    Text(formatTime(currentDuration)).font(.system(size: 10, weight: .bold)).foregroundColor(.gray).frame(width: 35)
                }.padding(.horizontal, 20).padding(.vertical, 8)
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
                
                HStack(spacing: 14) {
                    Button(action: {
                        selectFileFromDisk()
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    
                    if !isUniversalActive {
                        Button(action: { Task { await player.toggleShuffle() } }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(player.isShuffled ? .green : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: 360, height: 160)
    }

    private func barsView(count: Int, height: CGFloat) -> some View {
        HStack(spacing: 3) { ForEach(0..<count, id: \.self) { i in bar(index: i, height: height) } }
    }

    private func bar(index: Int, height: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let isPlaying = currentIsPlaying
            let phase = CGFloat(index) * 0.8 + CGFloat(t * 10)
            let amplitude = height * 0.35
            let barHeight = isPlaying ? (height * 0.2 + sin(phase) * amplitude + amplitude) : 4
            
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.8, green: 0.4, blue: 0.8))
                .frame(width: 3, height: barHeight)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Drag and Drop File Operation Views and Helpers

    private var isDroppedFileVideo: Bool {
        guard let url = droppedFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
    }
    
    private var isDroppedFileImage: Bool {
        guard let url = droppedFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif"].contains(ext)
    }

    private var sliderMinVal: Double {
        10.0
    }
    
    private var sliderMaxVal: Double {
        100.0
    }

    private var actionButtonGradient: LinearGradient {
        if selectedOperation == .compress {
            return LinearGradient(
                colors: [Color(red: 0.15, green: 0.55, blue: 1.0), Color(red: 0.0, green: 0.4, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 0.65, green: 0.35, blue: 0.95), Color(red: 0.5, green: 0.18, blue: 0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var actionButtonShadow: Color {
        selectedOperation == .compress ? Color.blue.opacity(0.3) : Color.purple.opacity(0.3)
    }

    private var fileOperationView: some View {
        VStack(spacing: 0) {
            // Compact Header Row
            HStack(spacing: 10) {
                Image(systemName: isDroppedFileVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isDroppedFileVideo ? .purple : .blue)
                
                Text(droppedFileURL?.lastPathComponent ?? "File")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let sizeString = getFileSizeString(url: droppedFileURL) {
                    Text("(\(sizeString))")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Discard Text Button
                Button(action: {
                    withAnimation {
                        resetFileStates()
                    }
                }) {
                    Text("Discard")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24) // Push below bezel curve
            
            // Side-by-side Options Row
            HStack(spacing: 16) {
                // Segmented control (Compress / Convert)
                HStack(spacing: 0) {
                    ForEach([FileOperation.compress, FileOperation.convert], id: \.self) { op in
                        Text(op == .compress ? "Compress" : "Convert")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(selectedOperation == op ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                            .background(
                                ZStack {
                                    if selectedOperation == op {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.12))
                                            .matchedGeometryEffect(id: "activeTab", in: tabAnimation)
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    selectedOperation = op
                                }
                            }
                    }
                }
                .padding(2)
                .frame(width: 130)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
                
                // Parameter control
                Group {
                    if selectedOperation == .compress {
                        let minVal = sliderMinVal
                        let maxVal = sliderMaxVal
                        
                        VStack(spacing: 2) {
                            HStack {
                                Text("Quality")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text("\(Int(compressionQuality))%")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(height: 3)
                                    
                                    Capsule()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat((compressionQuality - minVal) / (maxVal - minVal)), height: 3)
                                    
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 10, height: 10)
                                        .shadow(color: Color.black.opacity(0.4), radius: 1.5, y: 0.5)
                                        .offset(x: geo.size.width * CGFloat((compressionQuality - minVal) / (maxVal - minVal)) - 5)
                                }
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let percentage = Double(value.location.x / geo.size.width)
                                            let rawValue = minVal + percentage * (maxVal - minVal)
                                            compressionQuality = min(max(rawValue, minVal), maxVal)
                                        }
                                )
                            }
                            .frame(height: 10)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("Format:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Picker("", selection: $selectedExtension) {
                                if isDroppedFileVideo {
                                    Text("MP4").tag("mp4")
                                    Text("MKV").tag("mkv")
                                    Text("MOV").tag("mov")
                                } else {
                                    Text("PNG").tag("png")
                                    Text("JPG").tag("jpg")
                                    Text("WebP").tag("webp")
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .labelsHidden()
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            
            Spacer(minLength: 0)
            
            if isProcessing {
                // Loading View
                VStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Processing with FFmpeg...")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 12)
            } else if processSuccess {
                // Success View
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                    
                    Text("Processed Successfully!")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            openDownloadsFolder()
                        }) {
                            Text("Open Folder")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 90, height: 22)
                                .background(Color.green)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            withAnimation {
                                resetFileStates()
                            }
                        }) {
                            Text("Done")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 70, height: 22)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            } else if let err = errorMessage {
                // Error View
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    
                    Text("Error Processing File")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(err)
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .padding(.horizontal, 20)
                    
                    Button(action: {
                        errorMessage = nil
                    }) {
                        Text("Try Again")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 22)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 12)
            } else {
                // Large Action Button
                Button(action: {
                    processFile()
                }) {
                    Text(selectedOperation == .compress ? "Compress File" : "Convert File")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(actionButtonGradient)
                        .cornerRadius(6)
                        .shadow(color: actionButtonShadow, radius: 3, x: 0, y: 1.5)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 360, height: 160)
    }

    private func getFileSizeString(url: URL?) -> String? {
        guard let url = url else { return nil }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(size))
            }
        } catch {}
        return nil
    }


    private func resetFileStates() {
        droppedFileURL = nil
        isProcessing = false
        processSuccess = false
        errorMessage = nil
        processedFileURL = nil
        if !hasActivePlayback {
            size = .collapsed
            onSizeChange?(.collapsed)
        }
    }

    private func openDownloadsFolder() {
        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let spotDockURL = downloadsURL.appendingPathComponent("spotDock")
        NSWorkspace.shared.open(spotDockURL)
    }

    private func handleDroppedFile(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard error == nil,
                  let data = item as? Data,
                  let fileURL = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            
            let ext = fileURL.pathExtension.lowercased()
            let isImg = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif"].contains(ext)
            let isVid = ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
            
            if isImg || isVid {
                DispatchQueue.main.async {
                    self.droppedFileURL = fileURL
                    self.processSuccess = false
                    self.errorMessage = nil
                    self.processedFileURL = nil
                    
                    if isImg {
                        self.selectedExtension = ext == "png" ? "jpg" : "png"
                        self.compressionQuality = 80.0
                    } else {
                        self.selectedExtension = ext == "mp4" ? "mkv" : "mp4"
                        self.compressionQuality = 80.0
                    }
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        self.size = .expanded
                        self.onSizeChange?(.expanded)
                    }
                }
            }
        }
        return true
    }

    private func processFile() {
        guard let inputURL = droppedFileURL else { return }
        isProcessing = true
        errorMessage = nil
        processSuccess = false
        
        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let spotDockURL = downloadsURL.appendingPathComponent("spotDock")
        
        do {
            try fileManager.createDirectory(at: spotDockURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Could not create spotDock directory: \(error.localizedDescription)"
            isProcessing = false
            return
        }
        
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let targetExt = selectedOperation == .compress ? inputURL.pathExtension : selectedExtension
        let suffix = selectedOperation == .compress ? "_compressed" : "_converted"
        
        var destURL = spotDockURL.appendingPathComponent("\(baseName)\(suffix).\(targetExt)")
        var index = 1
        while fileManager.fileExists(atPath: destURL.path) {
            destURL = spotDockURL.appendingPathComponent("\(baseName)\(suffix)_\(index).\(targetExt)")
            index += 1
        }
        
        let finalDestURL = destURL
        let op = selectedOperation
        let isImg = isDroppedFileImage
        let qualityVal = compressionQuality
        
        Task.detached(priority: .userInitiated) {
            do {
                if op == .compress {
                    if isImg {
                        try await FFmpegUtility.compressImage(inputURL: inputURL, outputURL: finalDestURL, quality: Int(qualityVal))
                    } else {
                        try await FFmpegUtility.compressVideo(inputURL: inputURL, outputURL: finalDestURL, quality: Int(qualityVal))
                    }
                } else {
                    if isImg {
                        try await FFmpegUtility.convertImageFormat(inputURL: inputURL, outputURL: finalDestURL)
                    } else {
                        try await FFmpegUtility.convertVideoFormat(inputURL: inputURL, outputURL: finalDestURL)
                    }
                }
                
                await MainActor.run {
                    self.isProcessing = false
                    self.processSuccess = true
                    self.processedFileURL = finalDestURL
                    self.triggerHaptic()
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                    self.triggerHaptic()
                }
            }
        }
    }
    
    private var dropZoneView: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .padding(.leading, 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Drop Image or Video Here")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Supports PNG, JPG, WebP, MP4, MOV, MKV")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, miterLimit: 10, dash: [4, 4], dashPhase: 0))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 24)
        )
    }

    private func selectFileFromDisk() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [
            .image,
            .movie,
            .quickTimeMovie,
            UTType(filenameExtension: "mkv")!,
            UTType(filenameExtension: "webm")!
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let fileURL = openPanel.url {
                let ext = fileURL.pathExtension.lowercased()
                let isImg = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif"].contains(ext)
                let isVid = ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
                
                if isImg || isVid {
                    DispatchQueue.main.async {
                        self.droppedFileURL = fileURL
                        self.processSuccess = false
                        self.errorMessage = nil
                        self.processedFileURL = nil
                        
                        if isImg {
                            self.selectedExtension = ext == "png" ? "jpg" : "png"
                            self.compressionQuality = 80.0
                        } else {
                            self.selectedExtension = ext == "mp4" ? "mkv" : "mp4"
                            self.compressionQuality = 80.0
                        }
                        
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            self.size = .expanded
                            self.onSizeChange?(.expanded)
                        }
                    }
                }
            }
        }
    }
}

struct EyesView: View {
    var scale: CGFloat = 1.0
    var body: some View {
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
