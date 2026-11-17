//
//  MiniPlayerWindow.swift
//  Spotify
//

import SwiftUI
import AppKit
import QuartzCore
import CoreAudio
import IOKit.ps

class MiniPlayerWindowController: NSWindowController {
    private static let savedFrameKey = "MiniPlayerWindowFrame"
    
    convenience init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let contentView = NSHostingView(rootView: MiniPlayerView())
        window.contentView = contentView
        
        if let savedFrameString = UserDefaults.standard.string(forKey: MiniPlayerWindowController.savedFrameKey) {
            let parts = savedFrameString.components(separatedBy: ",")
            if parts.count == 4 {
                let x = CGFloat(Double(parts[0]) ?? 0)
                let y = CGFloat(Double(parts[1]) ?? 0)
                let w = CGFloat(Double(parts[2]) ?? 440)
                let h = CGFloat(Double(parts[3]) ?? 250)
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            }
        }

        self.init(window: window)
        window.delegate = WindowPositionSaver.shared
    }
    
    func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

class DynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKey() {}
    override func makeKeyAndOrderFront(_ sender: Any?) {
        self.orderFrontRegardless()
    }
}

// Custom HostingView that allows clicks to pass through its transparent areas
class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var onHitTest: ((NSPoint) -> Bool)?
    weak var controller: DynamicIslandWindowController?

    // Essential for macOS background panel: guarantees the very first click is delivered immediately!
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Fast-path: If outside interactive island area, return nil immediately so clicks pass through to apps/desktop
        guard let onHitTest = onHitTest, onHitTest(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    // Direct AppKit mouse handling: when collapsed, any click opens the island 100% of the time with zero lag!
    override func mouseDown(with event: NSEvent) {
        if let controller = controller, controller.islandSize == .collapsed {
            controller.expand()
            return
        }
        super.mouseDown(with: event)
    }
}

@MainActor
class DynamicIslandWindowController: NSObject, ObservableObject {
    @Published var islandSize: DynamicIslandSize = .collapsed
    var window: DynamicIslandPanel?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastExpandTime: TimeInterval = 0

    override init() {
        super.init()

        // Sized comfortably (480x205) for the expanded island wings, shadow, and tabs
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 205

        let panel = DynamicIslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let rootView = DynamicIslandView(size: Binding(get: { self.islandSize }, set: { [weak self] newSize in
            self?.islandSize = newSize
        }), onSizeChange: { _ in })

        // Use custom PassthroughHostingView
        let hostingView = PassthroughHostingView(rootView: rootView)
        hostingView.controller = self
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        
        hostingView.onHitTest = { [weak self] point in
            guard let self = self else { return false }
            let isExpanded = self.islandSize == .expanded
            let width: CGFloat = isExpanded ? 450 : 350
            let height: CGFloat = isExpanded ? 185 : 42
            
            let windowWidth = hostingView.bounds.width
            let windowHeight = hostingView.bounds.height
            
            // Island is pinned to top of the window with top overshoot (+35)
            let rect = NSRect(
                x: (windowWidth - width) / 2 - 15,
                y: windowHeight - height - 15,
                width: width + 30,
                height: height + 35
            )
            return rect.contains(point)
        }
        
        panel.contentView = hostingView

        self.window = panel
        self.centerOnScreen(panel)
        panel.orderFrontRegardless()

        // Setup click monitor for collapsing when clicking outside
        self.setupClickMonitor()

        // Listen for screen layout changes
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let window = self?.window {
                self?.centerOnScreen(window)
                window.orderFrontRegardless()
            }
        }
        
        // Listen for user display preference changes in Settings
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SpotDockDisplayChanged"), object: nil, queue: .main) { [weak self] _ in
            if let window = self?.window {
                self?.centerOnScreen(window)
                window.orderFrontRegardless()
            }
        }

        // Start hardware monitor (AirPods / Bluetooth & Battery / Charger connection alerts)
        HardwareMonitor.shared.start()
    }

    func expand() {
        guard islandSize == .collapsed else { return }
        lastExpandTime = ProcessInfo.processInfo.systemUptime
        triggerHaptic()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.islandSize = .expanded
        }
    }

    func collapse() {
        guard islandSize == .expanded else { return }
        triggerHaptic()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.islandSize = .collapsed
        }
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.islandSize == .expanded, let window = self.window else { return }
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            if let hostingView = window.contentView as? PassthroughHostingView<DynamicIslandView>,
               let onHitTest = hostingView.onHitTest {
                if !onHitTest(windowPoint) {
                    self.handleOutsideClick()
                }
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.islandSize == .expanded, let window = self.window else { return event }
            if event.window != window {
                self.handleOutsideClick()
            }
            return event
        }
    }

    func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
    }

    func close() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let local = localClickMonitor {
            NSEvent.removeMonitor(local)
            localClickMonitor = nil
        }
        window?.orderOut(nil)
    }

    private func centerOnScreen(_ window: NSWindow) {
        let targetDisplayID = UserDefaults.standard.string(forKey: "preferredDisplayID") ?? "main"
        let screens = NSScreen.screens
        let targetScreen: NSScreen
        
        if targetDisplayID == "builtIn", let builtIn = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            targetScreen = builtIn
        } else if let idNum = UInt32(targetDisplayID),
                  let match = screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == idNum }) {
            targetScreen = match
        } else {
            targetScreen = NSScreen.main ?? screens.first ?? window.screen ?? NSScreen.screens[0]
        }

        let screenFrame = targetScreen.frame
        let x = screenFrame.origin.x + (screenFrame.width - window.frame.width) / 2
        let y = screenFrame.origin.y + screenFrame.height - window.frame.height
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func handleOutsideClick() {
        guard islandSize == .expanded else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastExpandTime > 0.35 else { return }
        
        DispatchQueue.main.async {
            self.collapse()
        }
    }

    func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
}

// MARK: - Hardware Monitor (AirPods & Battery Status Banners)
class HardwareMonitor {
    static let shared = HardwareMonitor()
    private var lastDeviceID: AudioDeviceID = 0
    private var isListening = false
    private var lastChargingState: Bool? = nil
    private var powerTimer: Timer?
    
    func start() {
        guard !isListening else { return }
        isListening = true
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var initialDevice = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &initialDevice)
        self.lastDeviceID = initialDevice
        
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        
        startPowerMonitoring()
    }
    
    private func handleDeviceChange() {
        var defaultDevice = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDevice)
        guard status == noErr, defaultDevice != self.lastDeviceID else { return }
        self.lastDeviceID = defaultDevice
        
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        _ = AudioObjectGetPropertyData(defaultDevice, &nameAddress, 0, nil, &nameSize, &cfName)
        let deviceName = cfName as String
        guard !deviceName.isEmpty else { return }
        
        var transport: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        var transAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(defaultDevice, &transAddress, 0, nil, &transSize, &transport)
        let isBluetooth = (transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
        
        let icon: String
        let color: Color
        if deviceName.localizedCaseInsensitiveContains("airpod") {
            icon = "airpodspro"
            color = .blue
        } else if isBluetooth || deviceName.localizedCaseInsensitiveContains("headphone") || deviceName.localizedCaseInsensitiveContains("buds") {
            icon = "headphones"
            color = .blue
        } else if deviceName.localizedCaseInsensitiveContains("speaker") {
            icon = "speaker.wave.2.fill"
            color = .purple
        } else {
            icon = "hifispeaker.fill"
            color = .gray
        }
        
        Task { @MainActor in
            IslandBannerManager.shared.post(banner: IslandBanner(
                title: deviceName,
                subtitle: isBluetooth ? "Connected" : "Audio Output",
                systemImage: icon,
                accentColor: color
            ))
        }
    }
    
    private func startPowerMonitoring() {
        powerTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkPowerStatus()
        }
    }
    
    private func checkPowerStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
                
                if let last = self.lastChargingState {
                    if isCharging && !last {
                        Task { @MainActor in
                            IslandBannerManager.shared.post(banner: IslandBanner(
                                title: "Power Adapter Connected",
                                subtitle: "Charging (\(capacity)%)",
                                systemImage: "bolt.fill",
                                accentColor: .green
                            ))
                        }
                    } else if !isCharging && last {
                        Task { @MainActor in
                            IslandBannerManager.shared.post(banner: IslandBanner(
                                title: "Running on Battery",
                                subtitle: "\(capacity)% remaining",
                                systemImage: "battery.75",
                                accentColor: .orange
                            ))
                        }
                    }
                }
                self.lastChargingState = isCharging
                break
            }
        }
    }
}

class WindowPositionSaver: NSObject, NSWindowDelegate {
    static let shared = WindowPositionSaver()
    private let savedFrameKey = "MiniPlayerWindowFrame"
    
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)", forKey: savedFrameKey)
    }
}
