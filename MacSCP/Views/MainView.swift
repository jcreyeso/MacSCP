import SwiftUI
import AppKit

public struct MainView: View {
    @StateObject private var viewModel = AppViewModel()
    @ObservedObject private var l10n = LocalizationService.shared
    
    // Split view ratio state (Requirement 2)
    @State private var splitRatio: CGFloat = 0.50
    @State private var isDraggingSplitter: Bool = false
    @State private var isHoveringSplitter: Bool = false
    @State private var dragStartRatio: CGFloat = 0.50
    @State private var isShowingSettingsSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top Toolbar (Connection status, SSH Manager, Sudo elevation, About & Settings)
                topToolbar
                
                Divider()
                
                // Active file monitoring indicator banner
                if !viewModel.fileWatchService.monitoredFiles.isEmpty {
                    activeEditingBanner
                    Divider()
                }
                
                // Main Dual-Panel Split View (Requirement 2 & 4)
                GeometryReader { geometry in
                    let availableWidth = geometry.size.width
                    let centerBarWidth: CGFloat = 8
                    let minRatio: CGFloat = max(240 / availableWidth, 0.20)
                    let maxRatio: CGFloat = min(1.0 - (240 / availableWidth), 0.80)
                    let clampedRatio = min(max(splitRatio, minRatio), maxRatio)
                    
                    let contentWidth = max(availableWidth - centerBarWidth, 0)
                    let leftWidth = max(contentWidth * clampedRatio, 150)
                    let rightWidth = max(contentWidth * (1.0 - clampedRatio), 150)
                    
                    HStack(spacing: 0) {
                        // Left Panel: Local Files
                        FileBrowserPanel(
                            isRemote: false,
                            title: l10n[.localPanel],
                            currentPath: $viewModel.localPath,
                            items: viewModel.localFiles,
                            isLoading: viewModel.isLoadingLocal,
                            selectedPath: $viewModel.selectedLocalPath,
                            isConnected: true,
                            favorites: viewModel.localFavorites,
                            sortColumn: $viewModel.localSortColumn,
                            sortDirection: $viewModel.localSortDirection,
                            onSortChanged: { col, dir in
                                viewModel.setLocalSort(column: col, direction: dir)
                            },
                            onDoubleClick: { item in
                                viewModel.handleLocalItemDoubleClick(item)
                            },
                            onNavigate: { newPath in
                                viewModel.navigateLocal(to: newPath)
                            },
                            onNavigateUp: {
                                viewModel.navigateLocalUp()
                            },
                            onRefresh: {
                                viewModel.loadLocalFiles()
                            },
                            onGoHome: {
                                viewModel.navigateLocal(to: viewModel.localManager.homePath)
                            },
                            onToggleFavorite: { path in
                                viewModel.toggleLocalFavorite(path)
                            },
                            onRemoveFavorite: { path in
                                viewModel.removeLocalFavorite(path)
                            },
                            onCreateFolder: { name in
                                viewModel.createLocalFolder(named: name)
                            },
                            onRename: { item, newName in
                                viewModel.renameLocalItem(item, to: newName)
                            },
                            onUpload: { item in
                                viewModel.uploadLocalItem(item)
                            },
                            onDelete: { item in
                                viewModel.confirmDelete(item: item)
                            },
                            onCopyPath: { path in
                                viewModel.copyToClipboard(path)
                            }
                        )
                        .frame(width: leftWidth)
                        .frame(maxHeight: .infinity)
                        
                        // Center Transfer Controls Bar & Splitter
                        centerSplitterBar(
                            availableWidth: availableWidth,
                            minRatio: minRatio,
                            maxRatio: maxRatio
                        )
                        .frame(width: centerBarWidth)
                        .frame(maxHeight: .infinity)
                        
                        // Right Panel: Remote Files
                        FileBrowserPanel(
                            isRemote: true,
                            title: viewModel.currentConnection != nil ? "\(l10n[.remotePanel]) (\(viewModel.currentConnection!.alias))" : l10n[.remotePanel],
                            currentPath: $viewModel.remotePath,
                            items: viewModel.remoteFiles,
                            isLoading: viewModel.isLoadingRemote,
                            selectedPath: $viewModel.selectedRemotePath,
                            isConnected: viewModel.currentConnection != nil,
                            favorites: viewModel.remoteFavorites,
                            sortColumn: $viewModel.remoteSortColumn,
                            sortDirection: $viewModel.remoteSortDirection,
                            onSortChanged: { col, dir in
                                viewModel.setRemoteSort(column: col, direction: dir)
                            },
                            onDoubleClick: { item in
                                viewModel.handleRemoteItemDoubleClick(item)
                            },
                            onNavigate: { newPath in
                                viewModel.navigateRemote(to: newPath)
                            },
                            onNavigateUp: {
                                viewModel.navigateRemoteUp()
                            },
                            onRefresh: {
                                Task { await viewModel.loadRemoteFiles() }
                            },
                            onGoHome: viewModel.currentConnection != nil ? {
                                viewModel.navigateRemote(to: viewModel.remoteHomePath.isEmpty ? "~" : viewModel.remoteHomePath)
                            } : nil,
                            onToggleFavorite: { path in
                                viewModel.toggleRemoteFavorite(path)
                            },
                            onRemoveFavorite: { path in
                                viewModel.removeRemoteFavorite(path)
                            },
                            onCreateFolder: { name in
                                viewModel.createRemoteFolder(named: name)
                            },
                            onRename: { item, newName in
                                viewModel.renameRemoteItem(item, to: newName)
                            },
                            onDownload: { item in
                                viewModel.downloadRemoteItem(item)
                            },
                            onEditInNextpad: { item in
                                viewModel.editRemoteFileInNextpad(item: item)
                            },
                            onEditInNextpadWithSudo: { item in
                                viewModel.editRemoteFileInNextpad(item: item, withSudo: true)
                            },
                            onRemoteCopy: { item in
                                viewModel.promptRemoteCopy(for: item)
                            },
                            onDelete: { item in
                                viewModel.confirmDelete(item: item)
                            },
                            onCopyPath: { path in
                                viewModel.copyToClipboard(path)
                            }
                        )
                        .frame(width: rightWidth)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // Bottom Transfer Progress Bar
                if let transfer = viewModel.activeTransfer {
                    TransferProgressView(
                        progress: transfer,
                        onPause: { viewModel.pauseTransfer() },
                        onResume: { viewModel.resumeTransfer() },
                        onCancel: { viewModel.cancelTransfer() }
                    )
                }
            }
            
            // Toast Notification
            if let toast = viewModel.activeToast {
                ToastBannerView(toast: toast) {
                    withAnimation {
                        viewModel.activeToast = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 860, minHeight: 520)
        .sheet(isPresented: $viewModel.isShowingConnectionsSheet) {
            ConnectionsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingRemoteCopySheet) {
            RemoteCopySheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $viewModel.isShowingSudoPrompt) {
            sudoPasswordPromptSheet
        }
        .confirmationDialog(
            "\(l10n[.delete]) \(viewModel.itemToDelete?.isDirectory == true ? (l10n.currentLanguage == .spanish ? "la carpeta" : "folder") : (l10n.currentLanguage == .spanish ? "el archivo" : "file")) \"\(viewModel.itemToDelete?.name ?? "")\"?",
            isPresented: $viewModel.isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(l10n[.delete], role: .destructive) {
                viewModel.executeDelete()
            }
            Button(l10n[.cancel], role: .cancel) {
                viewModel.itemToDelete = nil
            }
        } message: {
            Text(viewModel.itemToDelete?.isRemote == true 
                 ? (l10n.currentLanguage == .spanish ? "Esta acción eliminará el elemento del servidor remoto de forma permanente." : "This action will permanently delete the item from the remote server.")
                 : (l10n.currentLanguage == .spanish ? "Esta acción eliminará el elemento de tu Mac de forma permanente." : "This action will permanently delete the item from your Mac."))
        }
        .onAppear {
            if viewModel.connections.isEmpty {
                viewModel.loadSavedConnections()
            }
        }
    }
    
    // MARK: - Toolbar
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // App Title / Logo
            HStack(spacing: 6) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16, weight: .bold))
                Text(l10n[.appName])
                    .font(.system(size: 15, weight: .bold))
                Text("v\(AppVersion.marketingVersion)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            // Connection Status
            if let conn = viewModel.currentConnection {
                HStack(spacing: 6) {
                    Circle()
                        .fill(conn.useSudoSFTP ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(l10n[.connectedTo])
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(conn.alias)
                        .font(.caption)
                        .fontWeight(.bold)
                    Text("(\(conn.displaySubtitle))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if conn.useSudoSFTP {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 9))
                            Text(l10n[.sudoRoot])
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(conn.useSudoSFTP ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                .cornerRadius(6)
                
                if !conn.useSudoSFTP {
                    Button(action: {
                        viewModel.connectWithSudo(to: conn)
                    }) {
                        Label(l10n.currentLanguage == .spanish ? "Elevar a Sudo" : "Elevate to Sudo", systemImage: "lock.shield")
                    }
                    .buttonStyle(.bordered)
                    .help(l10n.currentLanguage == .spanish ? "Reiniciar sesión SFTP con privilegios de superusuario (root)" : "Restart SFTP session with superuser (root) privileges")
                }
                
                Button(action: {
                    viewModel.disconnect()
                }) {
                    Label(l10n[.disconnect], systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text(l10n[.notConnected])
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            
            // Connection manager button
            Button(action: {
                viewModel.isShowingConnectionsSheet = true
            }) {
                Label(l10n[.sshConnections], systemImage: "server.rack")
            }
            .buttonStyle(.borderedProminent)
            .help(l10n[.selectSSHConnectionHelp])
            
            // Settings button
            Button(action: {
                isShowingSettingsSheet = true
            }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .help(l10n[.settings])
            
            // About button
            Button(action: {
                AppVersion.showAboutPanel()
            }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .help("\(l10n[.aboutMacSCP]) (v\(AppVersion.marketingVersion))")
            
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Center Splitter Bar
    private func centerSplitterBar(availableWidth: CGFloat, minRatio: CGFloat, maxRatio: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.35))
                .frame(width: 1)
            
            // Subtle grip pill indicator
            Capsule()
                .fill(isHoveringSplitter || isDraggingSplitter ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 3.5, height: 36)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(splitterDragGesture(availableWidth: availableWidth, minRatio: minRatio, maxRatio: maxRatio))
        .onHover { isHovered in
            isHoveringSplitter = isHovered
            if !isDraggingSplitter {
                if isHovered {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                splitRatio = 0.5
                dragStartRatio = 0.5
            }
        }
        .help(l10n.currentLanguage == .spanish ? "Arrastrar para cambiar proporción de paneles (Doble clic para centrar 50/50)" : "Drag to resize panels (Double-click to center 50/50)")
    }
    
    // MARK: - Splitter Drag Gesture
    private func splitterDragGesture(availableWidth: CGFloat, minRatio: CGFloat, maxRatio: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if !isDraggingSplitter {
                    isDraggingSplitter = true
                    dragStartRatio = splitRatio
                }
                NSCursor.resizeLeftRight.set()
                guard availableWidth > 0 else { return }
                let deltaRatio = gesture.translation.width / availableWidth
                let targetRatio = dragStartRatio + deltaRatio
                if minRatio < maxRatio {
                    splitRatio = min(max(targetRatio, minRatio), maxRatio)
                }
            }
            .onEnded { _ in
                isDraggingSplitter = false
                dragStartRatio = splitRatio
                if !isHoveringSplitter {
                    NSCursor.arrow.set()
                }
            }
    }
    
    // MARK: - Active Nextpad++ Editing Banner
    private var activeEditingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.outline")
                .foregroundColor(.orange)
            
            Text(l10n.currentLanguage == .spanish ? "Editando en Nextpad++:" : "Editing in Nextpad++:")
                .font(.caption)
                .fontWeight(.bold)
            
            ForEach(viewModel.fileWatchService.monitoredFiles) { file in
                HStack(spacing: 5) {
                    if file.isElevated {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    Text((file.remotePath as NSString).lastPathComponent)
                        .font(.caption)
                    
                    Button(action: {
                        viewModel.fileWatchService.removeMonitor(for: file.remotePath)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.currentLanguage == .spanish ? "Quitar aviso y finalizar monitoreo de este archivo" : "Dismiss notice and stop monitoring this file")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.18))
                .cornerRadius(4)
            }
            
            Text(l10n.currentLanguage == .spanish ? "(Cualquier cambio guardado se cargará automáticamente al servidor)" : "(Any saved changes will be automatically uploaded to the server)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.08))
    }
    
    // MARK: - Sudo Password Prompt Sheet
    private var sudoPasswordPromptSheet: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.sudoPromptTitle)
                        .font(.headline)
                    Text(viewModel.sudoPromptMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            SecureField(l10n.currentLanguage == .spanish ? "Contraseña de sudo en el servidor:" : "Sudo password on server:", text: $viewModel.sudoPromptPasswordInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !viewModel.sudoPromptPasswordInput.isEmpty {
                        viewModel.submitSudoPassword()
                    }
                }
            
            HStack {
                Button(l10n[.cancel]) {
                    viewModel.cancelSudoPassword()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(l10n.currentLanguage == .spanish ? "Aceptar" : "OK") {
                    viewModel.submitSudoPassword()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.sudoPromptPasswordInput.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
