import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

enum DynamicIslandSize {
    case collapsed
    case expanded
}

enum FileOperation {
    case compress
    case convert
}

enum IslandTab: String, CaseIterable, Identifiable {
    case player = "Player"
    case stash = "Quick Stash"
    case focus = "Focus Timer"
    case convert = "FFmpeg"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .player: return "music.note"
        case .stash: return "tray.full.fill"
        case .focus: return "timer"
        case .convert: return "bolt.fill"
        }
    }
}

// MARK: - Island Banner Alert Model & Manager
struct IslandBanner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let accentColor: Color
}

@MainActor
class IslandBannerManager: ObservableObject {
    static let shared = IslandBannerManager()
    @Published var currentBanner: IslandBanner? = nil
    private var dismissTask: Task<Void, Never>? = nil

    func post(banner: IslandBanner, duration: TimeInterval = 2.8) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentBanner = banner
        }
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if self.currentBanner?.id == banner.id {
                            self.currentBanner = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quick Stash / File Shelf Model & Manager
struct StashedItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    let name: String
    let sizeFormatted: String
    let icon: NSImage
    let dateAdded: Date
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.dateAdded = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.sizeFormatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            self.sizeFormatted = ""
        }
    }
}

@MainActor
class StashManager: ObservableObject {
    static let shared = StashManager()
    @Published var items: [StashedItem] = []
    
    func stash(urls: [URL]) {
        for url in urls {
            if !items.contains(where: { $0.url == url }) {
                items.append(StashedItem(url: url))
            }
        }
    }
    
    func remove(item: StashedItem) {
        items.removeAll { $0.id == item.id }
    }
    
    func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }
    
    func clear() {
        items.removeAll()
    }
}

// MARK: - Pomodoro / Focus Timer Manager
@MainActor
class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()
    
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var remainingSeconds: Int = 25 * 60
    @Published var totalDuration: Int = 25 * 60
    @Published var sessionLabel: String = "Focus"
    
    private var timer: AnyCancellable?
    
    func start(minutes: Int = 25, label: String = "Focus") {
        self.totalDuration = minutes * 60
        self.remainingSeconds = minutes * 60
        self.sessionLabel = label
        self.isRunning = true
        self.isPaused = false
        
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isRunning, !self.isPaused else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    self.finish()
                }
            }
    }
    
    func togglePlayPause() {
        guard isRunning else {
            start(minutes: 25, label: "Focus")
            return
        }
        isPaused.toggle()
    }
    
    func reset() {
        timer?.cancel()
        timer = nil
        isRunning = false
        isPaused = false
        remainingSeconds = totalDuration
    }
    
    private func finish() {
        timer?.cancel()
        timer = nil
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        NSSound(named: "Glass")?.play()
        IslandBannerManager.shared.post(banner: IslandBanner(
            title: "\(sessionLabel) Complete!",
            subtitle: "Well done! Take a break",
            systemImage: "timer",
            accentColor: .green
        ), duration: 4.0)
    }
    
    var timeString: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(totalDuration - remainingSeconds) / Double(totalDuration)
    }
}

// MARK: - Notch Shape
struct NotchShape: Shape {
    var progress: CGFloat // 0.0 (collapsed) to 1.0 (expanded)
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wingSize: CGFloat = 30 
        
        let cornerRadius: CGFloat = 12 + (progress * 10) // 12 -> 22
        let wingDepth: CGFloat = 18 + (progress * 6)    // 18 -> 24
        
        let leftEdge = wingSize
        let rightEdge = rect.width - wingSize
        
        path.move(to: CGPoint(x: 0, y: -100))
        path.addLine(to: CGPoint(x: 0, y: 0))
        
        path.addQuadCurve(to: CGPoint(x: leftEdge, y: wingDepth), 
                         control: CGPoint(x: leftEdge, y: 0))
        
        path.addLine(to: CGPoint(x: leftEdge, y: rect.height - cornerRadius))
        
        path.addArc(center: CGPoint(x: leftEdge + cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(90),
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: rightEdge - cornerRadius, y: rect.height))
        
        path.addArc(center: CGPoint(x: rightEdge - cornerRadius, y: rect.height - cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(90),
                    endAngle: .degrees(0),
                    clockwise: true)
        
        path.addLine(to: CGPoint(x: rightEdge, y: wingDepth))
        
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
    @ObservedObject var stashManager = StashManager.shared
    @ObservedObject var focusTimer = FocusTimerManager.shared
    @ObservedObject var bannerManager = IslandBannerManager.shared
    
    @Binding var size: DynamicIslandSize
    @State private var isHovering = false
    @State private var currentTab: IslandTab = .player
    @Namespace private var animation
    @Namespace private var tabNavAnimation
    var onSizeChange: ((DynamicIslandSize) -> Void)?

    // File Operation States (FFmpeg)
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
        player.useUniversalNowPlaying && !player.isPlaying && universalPlayer.isPlaying && !universalPlayer.trackName.isEmpty
    }

    private var hasActivePlayback: Bool {
        player.isPlaying || (universalPlayer.isPlaying && !universalPlayer.trackName.isEmpty)
    }

    private var currentPlatform: MediaPlatform {
        if player.isPlaying { return .spotify }
        return universalPlayer.mediaPlatform
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
            Image(systemName: currentPlatform.iconName).foregroundColor(.white.opacity(0.4))
        }
    }

    var body: some View {
        let isExpanded = size == .expanded
        
        ZStack(alignment: .top) {
            // 1. Background Notch Layer
            NotchShape(progress: isExpanded ? 1.0 : 0.0)
                .fill(Color.black)
                .overlay(
                    NotchShape(progress: isExpanded ? 1.0 : 0.0)
                        .stroke(Color.white.opacity(isExpanded ? 0.08 : 0), lineWidth: 0.5)
                )
                .frame(
                    width: isExpanded ? 440 : (bannerManager.currentBanner != nil ? 340 : (isHovering ? 330 : 300)),
                    height: isExpanded ? 175 : 30
                )
                .shadow(color: .black.opacity(0.45), 
                        radius: isExpanded ? 14 : 5, 
                        y: isExpanded ? 5 : 2)
        
            // 2. Content Layer
            ZStack {
                if isExpanded {
                    expandedView
                        .transition(.opacity)
                } else {
                    collapsedView
                        .contentShape(Rectangle())
                        .onTapGesture {
                            expand()
                        }
                        .transition(.opacity)
                }
            }
            .frame(
                width: isExpanded ? 400 : (bannerManager.currentBanner != nil ? 340 : (isHovering ? 330 : 300)), 
                height: isExpanded ? 175 : 30
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bannerManager.currentBanner)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedDrop) { providers in
            handleDroppedFiles(providers: providers)
        }
        .onChange(of: isTargetedDrop) { _, isHovered in
            if isHovered {
                expand()
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

    private func expand() {
        triggerHaptic()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            size = .expanded
        }
        onSizeChange?(.expanded)
    }

    private func collapse() {
        triggerHaptic()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            size = .collapsed
        }
        onSizeChange?(.collapsed)
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: - Collapsed View
    private var collapsedView: some View {
        ZStack {
            // Priority 1: Island Alert Banner (AirPods, Bluetooth, Power status)
            if let banner = bannerManager.currentBanner {
                HStack(spacing: 8) {
                    Image(systemName: banner.systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(banner.accentColor)
                        .shadow(color: banner.accentColor.opacity(0.6), radius: 4)
                        .padding(.leading, 32)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(banner.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let sub = banner.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }
            // Priority 2: Focus Timer Countdown
            else if focusTimer.isRunning {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.leading, 32)
                    
                    Text(focusTimer.timeString)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if hasActivePlayback {
                        barsView(count: 3, height: 10)
                            .padding(.trailing, 32)
                    } else {
                        Text(focusTimer.sessionLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange.opacity(0.8))
                            .padding(.trailing, 32)
                    }
                }
            }
            // Priority 3: Active Music Playback
            else if hasActivePlayback {
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
            }
            // Priority 4: Stashed Items Badge
            else if !stashManager.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                        .padding(.leading, 32)
                    
                    Text("\(stashManager.items.count) Stashed")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    Text("Drag out")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.trailing, 32)
                }
            }
            // Priority 5: Eyes View Idle Animation
            else {
                HStack {
                    EyesView(scale: 0.7)
                        .padding(.leading, 35)
                    Spacer()
                }
            }
        }
        .frame(width: bannerManager.currentBanner != nil ? 340 : (isHovering ? 330 : 300), height: 30)
    }

    // MARK: - Expanded View
    private var expandedView: some View {
        VStack(spacing: 0) {
            // Top Navigation & Tab Bar
            HStack(spacing: 8) {
                // Tab Switcher Buttons
                HStack(spacing: 2) {
                    tabButton(tab: .player, label: "Player", icon: currentPlatform.iconName)
                    tabButton(tab: .stash, label: "Stash (\(stashManager.items.count))", icon: "tray.full.fill")
                    tabButton(tab: .focus, label: focusTimer.isRunning ? focusTimer.timeString : "Focus", icon: "timer")
                    tabButton(tab: .convert, label: "FFmpeg", icon: "bolt.fill")
                }
                .padding(2)
                .background(Color.white.opacity(0.06))
                .cornerRadius(8)
                
                Spacer()
                
                // Collapse Button
                Button(action: { collapse() }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            
            // Tab Contents
            ZStack {
                switch currentTab {
                case .player:
                    playerExpandedView
                        .transition(.opacity)
                case .stash:
                    stashShelfView
                        .transition(.opacity)
                case .focus:
                    focusTimerView
                        .transition(.opacity)
                case .convert:
                    ffmpegExpandedView
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 390, height: 175)
    }

    private func tabButton(tab: IslandTab, label: String, icon: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                currentTab = tab
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .foregroundColor(currentTab == tab ? .white : .white.opacity(0.5))
            .background(
                ZStack {
                    if currentTab == tab {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.14))
                            .matchedGeometryEffect(id: "islandNavTab", in: tabNavAnimation)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Player View
    private var playerExpandedView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if hasActivePlayback {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)).frame(width: 50, height: 50)
                        currentAlbumArt
                            .matchedGeometryEffect(id: "albumArt", in: animation)
                            .frame(width: 44, height: 44).cornerRadius(6)
                    }
                } else {
                    EyesView(scale: 1.2).frame(width: 60, height: 50)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(hasActivePlayback ? currentTrackName : "Ready to Play")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(hasActivePlayback ? currentArtistName : "Spotify, Apple Music, YouTube or SoundCloud")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()
                if hasActivePlayback {
                    barsView(count: 4, height: 14)
                        .matchedGeometryEffect(id: "visualizer", in: animation)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            
            Spacer(minLength: 0)
            
            if hasActivePlayback && currentDuration > 0 {
                HStack(spacing: 8) {
                    Text(formatTime(currentProgress)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray).frame(width: 32)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(currentPlatform.brandColor.opacity(0.85))
                                .frame(width: currentDuration > 0 ? geo.size.width * CGFloat(min(max(currentProgress / currentDuration, 0), 1)) : 0, height: 3)
                        }.padding(.top, 3)
                    }.frame(height: 8)
                    Text(formatTime(currentDuration)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray).frame(width: 32)
                }.padding(.horizontal, 16).padding(.vertical, 4)
            }
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "headphones").font(.system(size: 12, weight: .medium))
                    Text("\(currentVolume)%").font(.system(size: 10, weight: .bold))
                }.foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                HStack(spacing: 18) {
                    Button(action: { previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { togglePlay() }) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.12)).frame(width: 36, height: 36)
                            Image(systemName: currentIsPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Platform Badge
                HStack(spacing: 4) {
                    Image(systemName: currentPlatform.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(currentPlatform.brandColor)
                    Text(currentPlatform.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(currentPlatform.brandColor.opacity(0.15))
                .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Tab 2: Quick Stash Shelf View
    private var stashShelfView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Temporary File Shelf")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if !stashManager.items.isEmpty {
                    Button(action: { stashManager.clear() }) {
                        Text("Clear All")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            
            if stashManager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                        .foregroundColor(.cyan.opacity(0.6))
                    Text("Drag files into this shelf to park them")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Hold files while switching desktops, spaces, or apps")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .padding(.horizontal, 16)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stashManager.items) { item in
                            stashedItemCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .frame(height: 85)
            }
            
            HStack {
                Text("Tip: Drag item cards directly into Finder, Slack, or Browser")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private func stashedItemCard(item: StashedItem) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .padding(.top, 4)
                
                Button(action: { stashManager.remove(item: item) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -2)
            }
            
            Text(item.name)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 65)
            
            Text(item.sizeFormatted)
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
        .padding(6)
        .frame(width: 76, height: 78)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        // Native macOS drag-out support: drag directly into Finder or any application!
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Button("Remove from Stash") {
                stashManager.remove(item: item)
            }
        }
    }

    // MARK: - Tab 3: Focus / Pomodoro Timer View
    private var focusTimerView: some View {
        VStack(spacing: 6) {
            HStack {
                Text(focusTimer.sessionLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                Spacer()
                Text(focusTimer.isRunning ? (focusTimer.isPaused ? "Paused" : "Active") : "Ready")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(focusTimer.isRunning ? (focusTimer.isPaused ? .yellow : .green) : .gray)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            
            HStack(spacing: 20) {
                // Large Clock Display
                VStack(spacing: 2) {
                    Text(focusTimer.timeString)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                    
                    // Linear progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(Color.orange)
                                .frame(width: geo.size.width * CGFloat(focusTimer.progress), height: 3)
                        }
                    }
                    .frame(height: 4)
                    .frame(width: 110)
                }
                
                // Presets Grid
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        presetButton(label: "25m Focus", minutes: 25, type: "Focus")
                        presetButton(label: "15m Sprint", minutes: 15, type: "Sprint")
                    }
                    HStack(spacing: 6) {
                        presetButton(label: "45m Deep", minutes: 45, type: "Deep Work")
                        presetButton(label: "5m Break", minutes: 5, type: "Break")
                    }
                }
                
                // Play / Pause / Reset
                VStack(spacing: 6) {
                    Button(action: { focusTimer.togglePlayPause() }) {
                        ZStack {
                            Circle().fill(Color.orange.opacity(0.2)).frame(width: 32, height: 32)
                            Image(systemName: focusTimer.isRunning && !focusTimer.isPaused ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { focusTimer.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private func presetButton(label: String, minutes: Int, type: String) -> some View {
        Button(action: {
            focusTimer.start(minutes: minutes, label: type)
        }) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 4: FFmpeg Tools View
    private var ffmpegExpandedView: some View {
        Group {
            if isTargetedDrop {
                dropZoneView
            } else if droppedFileURL != nil {
                fileOperationView
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                        Text("FFmpeg Media Tools")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("Select File...") { selectFileFromDisk() }
                            .font(.system(size: 9, weight: .bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.purple.opacity(0.6))
                        Text("Drop any Image or Video to compress or convert")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Text("MP4, MOV, MKV, PNG, JPG, WebP")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .padding(.horizontal, 16)
                    )
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func barsView(count: Int, height: CGFloat) -> some View {
        WaveformBarsView(isPlaying: currentIsPlaying, count: count, height: height)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - FFmpeg Operations and File Handling
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

    private var fileOperationView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isDroppedFileVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isDroppedFileVideo ? .purple : .blue)
                
                Text(droppedFileURL?.lastPathComponent ?? "File")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let sizeString = getFileSizeString(url: droppedFileURL) {
                    Text("(\(sizeString))")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: { resetFileStates() }) {
                    Text("Cancel")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            
            HStack(spacing: 12) {
                // Operation switcher
                HStack(spacing: 0) {
                    ForEach([FileOperation.compress, FileOperation.convert], id: \.self) { op in
                        Text(op == .compress ? "Compress" : "Convert")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(selectedOperation == op ? .white : .white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .frame(height: 18)
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
                .frame(width: 120)
                .background(Color.white.opacity(0.04))
                .cornerRadius(5)
                
                // Option details
                if selectedOperation == .compress {
                    VStack(spacing: 1) {
                        HStack {
                            Text("Quality").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("\(Int(compressionQuality))%").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                                Capsule().fill(Color.blue).frame(width: geo.size.width * CGFloat((compressionQuality - 10.0) / 90.0), height: 3)
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0).onChanged { val in
                                    let perc = Double(val.location.x / geo.size.width)
                                    compressionQuality = min(max(10.0 + perc * 90.0, 10.0), 100.0)
                                }
                            )
                        }.frame(height: 8)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("Format:").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.5))
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            Spacer(minLength: 0)
            
            if isProcessing {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.7)
            } else if processSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 11))
                    Text("Saved to Downloads/spotDock").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                    Button("Open") { openDownloadsFolder() }.font(.system(size: 9, weight: .bold)).buttonStyle(.plain).foregroundColor(.blue)
                }
                .padding(.bottom, 6)
            } else if let error = errorMessage {
                Text(error).font(.system(size: 8)).foregroundColor(.red).lineLimit(1).padding(.bottom, 6)
            } else {
                Button(action: { processFile() }) {
                    Text(selectedOperation == .compress ? "Compress Media" : "Convert Media")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(selectedOperation == .compress ? Color.blue : Color.purple)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
        }
    }

    private var dropZoneView: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill").font(.system(size: 18)).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Drop File Here").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                Text("Park in Stash or Process with FFmpeg").font(.system(size: 8)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func getFileSizeString(url: URL?) -> String? {
        guard let url = url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func resetFileStates() {
        droppedFileURL = nil
        isProcessing = false
        processSuccess = false
        errorMessage = nil
        processedFileURL = nil
    }

    private func openDownloadsFolder() {
        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let spotDockURL = downloadsURL.appendingPathComponent("spotDock")
        NSWorkspace.shared.open(spotDockURL)
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                defer { group.leave() }
                guard error == nil,
                      let data = item as? Data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                collectedURLs.append(fileURL)
            }
        }
        
        group.notify(queue: .main) {
            guard !collectedURLs.isEmpty else { return }
            
            // If current tab is FFmpeg or single image/vid dropped when idle
            if self.currentTab == .convert && collectedURLs.count == 1 {
                let fileURL = collectedURLs[0]
                let ext = fileURL.pathExtension.lowercased()
                let isImg = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "gif"].contains(ext)
                let isVid = ["mp4", "mov", "mkv", "avi", "webm", "m4v"].contains(ext)
                if isImg || isVid {
                    self.droppedFileURL = fileURL
                    self.selectedExtension = isImg ? (ext == "png" ? "jpg" : "png") : (ext == "mp4" ? "mkv" : "mp4")
                    self.compressionQuality = 80.0
                    self.expand()
                    return
                }
            }
            
            // Otherwise, park in Quick Stash!
            self.stashManager.stash(urls: collectedURLs)
            self.currentTab = .stash
            self.expand()
            IslandBannerManager.shared.post(banner: IslandBanner(
                title: "\(collectedURLs.count) File\(collectedURLs.count > 1 ? "s" : "") Stashed",
                subtitle: "Ready to drag out anywhere",
                systemImage: "tray.full.fill",
                accentColor: .cyan
            ))
        }
        return true
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
                DispatchQueue.main.async {
                    self.droppedFileURL = fileURL
                    self.processSuccess = false
                    self.errorMessage = nil
                    self.processedFileURL = nil
                    self.currentTab = .convert
                    self.expand()
                }
            }
        }
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
            errorMessage = error.localizedDescription
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
                    IslandBannerManager.shared.post(banner: IslandBanner(
                        title: "Media Processed Successfully",
                        subtitle: "Saved to Downloads/spotDock",
                        systemImage: "checkmark.circle.fill",
                        accentColor: .green
                    ))
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
}

// MARK: - Waveform Bars View
struct WaveformBarsView: View {
    let isPlaying: Bool
    let count: Int
    let height: CGFloat

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 0.06)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<count, id: \.self) { i in
                        let phase = CGFloat(i) * 0.85 + CGFloat(t * 9.0)
                        let amplitude = height * 0.35
                        let barHeight = max(3.0, height * 0.2 + sin(phase) * amplitude + amplitude)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(red: 0.8, green: 0.4, blue: 0.8))
                            .frame(width: 3, height: barHeight)
                    }
                }
            }
        } else {
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.8, green: 0.4, blue: 0.8).opacity(0.4))
                        .frame(width: 3, height: 3)
                }
            }
        }
    }
}

// MARK: - Eyes View
struct EyesView: View {
    var scale: CGFloat = 1.0
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35)) { timeline in
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
