import SwiftUI
import AppKit

// MARK: - App Version Configuration
public enum AppVersion {
    public static let marketingVersion = "1.1.0"
    public static let buildNumber = "2026.10.13"
    public static let appName = "MacSCP"
    public static let githubURL = URL(string: "https://github.com/jcreyeso/MacSCP")!
    
    public static var displayString: String {
        return "Versión \(marketingVersion) (\(buildNumber))"
    }
    
    @MainActor
    public static func showAboutPanel() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let creditsString = NSMutableAttributedString()
        let isSpanish = LocalizationService.shared.currentLanguage == .spanish
        
        let description = NSAttributedString(
            string: isSpanish
                ? "Cliente nativo SSH/SFTP para macOS\nTransferencias seguras, edición remota integrada con Nextpad++ y soporte para elevación Sudo.\nLicencia de código abierto GNU GPLv3.\n\n"
                : "Native SSH/SFTP client for macOS\nSecure transfers, live remote editing with Nextpad++, and Sudo root elevation.\nOpen Source GNU General Public License v3.0 (GPLv3).\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        creditsString.append(description)
        
        let repoLink = NSAttributedString(
            string: "GitHub",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .link: githubURL,
                .foregroundColor: NSColor.linkColor
            ]
        )
        creditsString.append(repoLink)
        
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appName,
            .applicationVersion: marketingVersion,
            .version: buildNumber,
            .credits: creditsString
        ]
        
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
}

@main
struct MacSCPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var l10n = LocalizationService.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(l10n[.aboutMacSCP]) {
                    AppVersion.showAboutPanel()
                }
            }
            SidebarCommands()
            CommandGroup(replacing: .newItem) { }
        }
        
        Settings {
            SettingsView()
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
        
        // Set main window title if available
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.title = "MacSCP"
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
