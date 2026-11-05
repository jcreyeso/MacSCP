import AppKit
import SwiftUI

/// Strip above the toolbar listing one tab per connection.
struct TabBarView: View {
    @ObservedObject var manager: TabManager
    @ObservedObject private var l10n = LocalizationService.shared
    
    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(manager.tabs) { tab in
                        ConnectionTabButton(
                            viewModel: tab,
                            isSelected: tab.id == manager.selectedTabID,
                            canClose: manager.tabs.count > 1,
                            onSelect: { manager.select(tab) },
                            onClose: { manager.requestClose(tab) }
                        )
                    }
                }
            }
            
            Button(action: { manager.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(l10n.currentLanguage == .spanish ? "Nueva pestaña (⌘T)" : "New tab (⌘T)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.underPageBackgroundColor))
    }
}

private struct ConnectionTabButton: View {
    @ObservedObject var viewModel: AppViewModel
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @ObservedObject private var l10n = LocalizationService.shared
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 12, height: 12)
            
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)
            
            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isHovering ? 1 : 0)
                .help(l10n.currentLanguage == .spanish ? "Cerrar pestaña (⌘W)" : "Close tab (⌘W)")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color(NSColor.windowBackgroundColor) : (isHovering ? Color.secondary.opacity(0.12) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .help(helpText)
    }
    
    private var title: String {
        viewModel.currentConnection?.alias
            ?? (l10n.currentLanguage == .spanish ? "Nueva pestaña" : "New Tab")
    }
    
    private var helpText: String {
        viewModel.currentConnection?.displaySubtitle ?? l10n[.notConnected]
    }
    
    /// Shows what matters most in a tab, including one that is not on screen.
    @ViewBuilder
    private var statusIcon: some View {
        if viewModel.isShowingSudoPrompt {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        } else if viewModel.hasUnseenError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
        } else if viewModel.isConnecting || viewModel.activeTransfer != nil {
            ProgressView()
                .controlSize(.mini)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }
    
    private var statusColor: Color {
        guard let connection = viewModel.currentConnection else {
            return Color.secondary.opacity(0.4)
        }
        return connection.useSudoSFTP ? .orange : .green
    }
}

/// Menu items and keyboard shortcuts for working with tabs.
struct TabCommands: Commands {
    @ObservedObject var manager: TabManager
    @ObservedObject var l10n = LocalizationService.shared
    
    private var isSpanish: Bool { l10n.currentLanguage == .spanish }
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(isSpanish ? "Nueva pestaña" : "New Tab") {
                manager.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button(isSpanish ? "Cerrar" : "Close") {
                manager.closeCurrentTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
        CommandGroup(before: .windowList) {
            Button(isSpanish ? "Pestaña siguiente" : "Next Tab") {
                manager.selectTab(offset: 1)
            }
            .keyboardShortcut(.tab, modifiers: .control)
            Button(isSpanish ? "Pestaña anterior" : "Previous Tab") {
                manager.selectTab(offset: -1)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
        }
    }
}

/// Reports the window that hosts the view.
struct WindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(onWindowChange: onWindowChange)
    }
    
    func updateNSView(_ view: WindowReaderView, context: Context) {}
    
    final class WindowReaderView: NSView {
        private let onWindowChange: (NSWindow?) -> Void
        
        init(onWindowChange: @escaping (NSWindow?) -> Void) {
            self.onWindowChange = onWindowChange
            super.init(frame: .zero)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }
        
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange(window)
        }
    }
}
