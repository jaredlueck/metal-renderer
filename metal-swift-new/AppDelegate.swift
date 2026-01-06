//
//  AppDelegate.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-08.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var window: NSWindow!
        
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create and show the main application window programmatically
        let frame = NSMakeRect(0, 0, 1000, 1000)
        self.window = NSWindow(
            contentRect:frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "metal-swift-new"
        let viewController = GameViewController()
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
         
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}
