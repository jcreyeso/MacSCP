import SwiftUI
import AppKit

@main
struct MacSCPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        
        // Ensure app icon is displayed in Dock and App Switcher across all launch environments
        if let iconImage = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = iconImage
        } else if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let iconImage = NSImage(contentsOf: icnsURL) {
            NSApplication.shared.applicationIconImage = iconImage
        } else {
            #if SWIFT_PACKAGE
            if let moduleIcnsURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
               let iconImage = NSImage(contentsOf: moduleIcnsURL) {
                NSApplication.shared.applicationIconImage = iconImage
            }
            #endif
        }
        
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

