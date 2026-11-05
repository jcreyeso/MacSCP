import AppKit
import SwiftUI

/// Owns the open tabs. Each tab is an `AppViewModel` with its own SSH connection and panels.
@MainActor
public final class TabManager: ObservableObject {
    @Published public private(set) var tabs: [AppViewModel]
    @Published public private(set) var selectedTabID: UUID
    /// Tab waiting for the user to confirm closing it, because closing would interrupt its work.
    @Published public var tabPendingClose: AppViewModel?
    
    /// The window showing the tabs, used to tell it apart from Settings and to detect open sheets.
    public weak var window: NSWindow? {
        didSet {
            // This is the app's only window, so its close button quits, with the same warning as Cmd+Q.
            let closeButton = window?.standardWindowButton(.closeButton)
            closeButton?.target = NSApp
            closeButton?.action = #selector(NSApplication.terminate(_:))
        }
    }
    
    public init() {
        let firstTab = AppViewModel()
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
    }
    
    public var selectedTab: AppViewModel {
        tabs.first { $0.id == selectedTabID } ?? tabs[0]
    }
    
    public func newTab() {
        guard !isBlockedBySheet else { return }
        let tab = AppViewModel(localPath: selectedTab.localPath)
        tab.isShowingConnectionsSheet = true
        tabs.append(tab)
        activate(tab)
    }
    
    public func select(_ tab: AppViewModel) {
        guard !isBlockedBySheet, tab.id != selectedTabID else { return }
        activate(tab)
    }
    
    /// Moves through the tabs by `offset`, wrapping around at either end.
    public func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }
    
    /// Closes the tab, asking first if a transfer or a remote edit would be interrupted.
    public func requestClose(_ tab: AppViewModel) {
        guard !isBlockedBySheet, tabs.count > 1 else { return }
        if tab.hasActiveWork {
            select(tab)
            tabPendingClose = tab
        } else {
            close(tab)
        }
    }
    
    public func confirmPendingClose() {
        guard let tab = tabPendingClose else { return }
        tabPendingClose = nil
        close(tab)
    }
    
    /// Cmd+W: closes the current tab, quits on the last tab, or closes another window such as Settings.
    public func closeCurrentTabOrWindow() {
        guard let keyWindow = NSApp.keyWindow else { return }
        guard keyWindow === window else {
            keyWindow.performClose(nil)
            return
        }
        if tabs.count > 1 {
            requestClose(selectedTab)
        } else if !isBlockedBySheet {
            NSApp.terminate(nil)
        }
    }
    
    /// Asks before quitting if that would stop transfers or remote edits. Returns whether to quit.
    public func confirmQuit() -> Bool {
        let transfers = tabs.filter(\.hasActiveTransfer).count
        let editedFiles = Set(FileWatchService.shared.monitoredFiles.map(\.localURL))
        guard transfers > 0 || !editedFiles.isEmpty else { return true }
        
        let isSpanish = LocalizationService.shared.currentLanguage == .spanish
        var details: [String] = []
        if !editedFiles.isEmpty {
            let names = editedFiles.map(\.lastPathComponent).sorted().joined(separator: ", ")
            details.append(isSpanish
                ? "Archivos en edición (\(editedFiles.count)): \(names). Sus copias locales se eliminarán, junto con cualquier cambio que no se haya subido, y lo que guardes después en Nextpad++ no llegará al servidor."
                : "Files being edited (\(editedFiles.count)): \(names). Their local copies will be deleted, along with any changes that weren't uploaded, and anything you save afterwards in Nextpad++ won't reach the server.")
        }
        if transfers > 0 {
            details.append(isSpanish
                ? "Transferencias en curso: \(transfers). Se cancelarán."
                : "Transfers in progress: \(transfers). They will be cancelled.")
        }
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isSpanish ? "¿Salir de MacSCP?" : "Quit MacSCP?"
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: LocalizationService.shared[.cancel])
        let quitButton = alert.addButton(withTitle: isSpanish ? "Salir" : "Quit")
        quitButton.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }
    
    private var isBlockedBySheet: Bool {
        window?.attachedSheet != nil
    }
    
    private func close(_ tab: AppViewModel) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.closeSession()
        if tab.id == selectedTabID {
            activate(tabs[min(index, tabs.count - 1)])
        }
    }
    
    private func activate(_ tab: AppViewModel) {
        selectedTab.isTabActive = false
        selectedTabID = tab.id
        tab.tabDidBecomeActive()
    }
}
