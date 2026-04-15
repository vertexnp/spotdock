//
//  MiniPlayerWindow.swift
//  Spotify
//

import SwiftUI
import AppKit

class MiniPlayerWindowController: NSWindowController {
    private static let savedFrameKey = "MiniPlayerWindowFrame"
    
    convenience init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Restore saved position or use center as default
        if let savedFrameString = UserDefaults.standard.string(forKey: MiniPlayerWindowController.savedFrameKey) {
            let parts = savedFrameString.split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 {
                window.setFrame(NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]), display: true)
            } else {
                window.center()
            }
        } else {
            window.center()
        }
        
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = false

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))

        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let contentView = NSHostingView(rootView: MiniPlayerView())
        window.contentView = contentView
        window.setContentSize(contentView.fittingSize)

        // Save position when window moves
        window.delegate = WindowPositionSaver.shared

        self.init(window: window)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // Set delegate after window is loaded
        window?.delegate = WindowPositionSaver.shared
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

class WindowPositionSaver: NSObject, NSWindowDelegate {
    static let shared = WindowPositionSaver()
    private let savedFrameKey = "MiniPlayerWindowFrame"
    
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)", forKey: savedFrameKey)
    }
}
