//
//  MiniPlayerWindow.swift
//  Spotify
//

import SwiftUI
import AppKit

class MiniPlayerWindowController: NSWindowController {
    convenience init() {
        // Reduced size for medium widget feel (358x170 content + padding for shadow)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false 
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = false

        // Use backstopMenu level: higher than desktop widgets but lower than normal apps.
        // This ensures it stays behind Safari, Finder, etc.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))

        // Widget behavior: All spaces, stationary (pinned to desktop), ignores cycle
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        
        let contentView = NSHostingView(rootView: MiniPlayerView())
        window.contentView = contentView
        
        // Auto-resize window to fit content
        window.setContentSize(contentView.fittingSize)
        
        self.init(window: window)
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
