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

@MainActor
class DynamicIslandWindowController: NSObject, ObservableObject {
    @Published var islandSize: DynamicIslandSize = .collapsed
    var window: DynamicIslandPanel?
    private var clickMonitor: Any?

    override init() {
        super.init()
        
        let panel = DynamicIslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 30),
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
            self?.resizeWindow(for: newSize)
        }), onSizeChange: { [weak self] size in
            self?.resizeWindow(for: size)
        })

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.layer?.backgroundColor = .clear
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 30)
        panel.contentView = hostingView
        
        self.window = panel
        self.centerOnScreen(panel)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let window = self?.window {
                self?.centerOnScreen(window)
                window.orderFrontRegardless()
            }
        }
    }

    func showWindow(_ sender: Any?) {
        window?.orderFrontRegardless()
    }
    
    func close() {
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
        guard let window = window, let screen = NSScreen.main else { return }
        
        if size == .expanded {
            self.clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.handleOutsideClick()
            }
        } else {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                self.clickMonitor = nil
            }
        }

        let newWidth: CGFloat = (size == .collapsed) ? 320 : 420
        let newHeight: CGFloat = (size == .collapsed) ? 30 : 179.5
        
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - newWidth) / 2
        let topEdge = screenFrame.origin.y + screenFrame.height
        let y = topEdge - newHeight
        
        let newFrame = NSRect(x: x, y: y, width: newWidth, height: newHeight)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
        window.orderFrontRegardless()
    }
    
    private func handleOutsideClick() {
        guard islandSize == .expanded else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.islandSize = .collapsed
            }
            self.resizeWindow(for: .collapsed)
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
