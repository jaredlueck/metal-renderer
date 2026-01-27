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
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "metal-renderer"
        let viewController = GameViewController()
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        // Create the main menu bar
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // Create the "File" menu item that appears in the menu bar
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        // Create the actual "File" submenu
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        // Add a "Save" command to the File submenu
        let saveItem = NSMenuItem(
            title: "Save",
            action: #selector(Editor.saveScene(_:)),
            keyEquivalent: "s"
        )
        // Set the target to your responder (AppDelegate or a document/controller)
        saveItem.target = viewController.editor
        fileMenu.addItem(saveItem)
                
    }

    func applicationWillTerminate(_ aNotification: Notification) {
         
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}
