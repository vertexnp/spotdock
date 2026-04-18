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

class DynamicIslandWindowController: NSWindowController, ObservableObject {
    @Published var islandSize: DynamicIslandSize = .collapsed
    private var clickMonitor: Any?

    convenience init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 30.5),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isMovableByWindowBackground = false 
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = true
        window.level = .statusBar

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]

        self.init(window: window)

        let contentView = NSHostingView(rootView: DynamicIslandView(size: Binding(get: { self.islandSize }, set: { self.islandSize = $0 }), onSizeChange: { [weak self] size in
            self?.resizeWindow(for: size)
        }))
        
        contentView.translatesAutoresizingMaskIntoConstraints = true
        window.contentView = contentView
        
        self.centerOnScreen(window)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let window = self?.window {
                self?.centerOnScreen(window)
            }
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

        let newWidth: CGFloat = (size == .collapsed) ? 240 : 420
        let newHeight: CGFloat = (size == .collapsed) ? 30.5 : 179.5
        
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - newWidth) / 2
        let topEdge = screenFrame.origin.y + screenFrame.height
        let y = topEdge - newHeight
        
        let newFrame = NSRect(x: x, y: y, width: newWidth, height: newHeight)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
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
    
    private func centerOnScreen(_ window: NSWindow) {
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowFrame = window.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + screenFrame.height - windowFrame.height
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    func toggle() {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
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
