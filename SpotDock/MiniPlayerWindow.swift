//
//  MiniPlayerWindow.swift
//  Spotify
//

import SwiftUI
import AppKit
import QuartzCore

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view == self {
            // Only return self if the point is within our interactive area
            if let onHitTest = onHitTest, onHitTest(point) {
                return self
            }
            return nil
        }
        return view
    }
}

@MainActor
class DynamicIslandWindowController: NSObject, ObservableObject {
    @Published var islandSize: DynamicIslandSize = .collapsed
    var window: DynamicIslandPanel?
    private var clickMonitor: Any?

    override init() {
        super.init()

        let panel = DynamicIslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
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

        // Use our custom PassthroughHostingView
        let hostingView = PassthroughHostingView(rootView: rootView)
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        
        hostingView.onHitTest = { [weak self] point in
            guard let self = self else { return false }
            let isExpanded = self.islandSize == .expanded
            let width: CGFloat = isExpanded ? 420 : 320
            let height: CGFloat = isExpanded ? 160 : 30
            
            // The island is centered horizontally in the 800px window
            // adding some padding to make it easier to hit
            let rect = NSRect(
                x: (800 - width) / 2 - 20,
                y: 300 - height - 20,
                width: width + 40,
                height: height + 20 // Only add padding to bottom/sides, not top (bezel)
            )
            return rect.contains(point)
        }
        
        panel.contentView = hostingView

        self.window = panel
        self.centerOnScreen(panel)
        panel.orderFrontRegardless()

        // Setup click monitor for collapsing when clicking outside
        self.setupClickMonitor()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let window = self?.window {
                self?.centerOnScreen(window)
                window.orderFrontRegardless()
            }
        }
    }

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.islandSize == .expanded else { return }
            
            // Convert click location to window coordinates
            if let window = self.window {
                let screenPoint = NSEvent.mouseLocation
                let windowPoint = window.convertPoint(fromScreen: screenPoint)
                
                // Check if click was NOT on the hosting view's interactive area
                if let hostingView = window.contentView as? PassthroughHostingView<DynamicIslandView>,
                   let onHitTest = hostingView.onHitTest {
                    if !onHitTest(windowPoint) {
                        self.handleOutsideClick()
                    }
                }
            }
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
        window?.orderOut(nil)
    }

    private func centerOnScreen(_ window: NSWindow) {
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let x = screenFrame.origin.x + (screenFrame.width - window.frame.width) / 2
            let y = screenFrame.origin.y + screenFrame.height - window.frame.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func resizeWindow(for size: DynamicIslandSize) {
        // Window is fixed size now, internal view animates
    }

    func handleOutsideClick() {
        guard islandSize == .expanded else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.islandSize = .collapsed
            }
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

class WindowPositionSaver: NSObject, NSWindowDelegate {
    static let shared = WindowPositionSaver()
    private let savedFrameKey = "MiniPlayerWindowFrame"
    
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)", forKey: savedFrameKey)
    }
}
