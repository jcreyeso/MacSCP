import Foundation
import SwiftUI
import AppKit

public enum ToastType {
    case info
    case success
    case error
    
    var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}

public struct ToastItem: Identifiable {
    public let id = UUID()
    public let message: String
    public let type: ToastType
}

@MainActor
public final class AppViewModel: ObservableObject {
    // MARK: - SSH Connections
    @Published public var connections: [SSHConnection] = []
    @Published public var connectionSearchText: String = ""
    @Published public var isConnecting: Bool = false
    @Published public var currentConnection: SSHConnection?
    @Published public var isShowingConnectionsSheet: Bool = false
    
    // MARK: - Dual Browser Navigation
    @Published public var localPath: String = ""
    @Published public var localFiles: [FileItem] = []
    @Published public var selectedLocalPath: String?
    @Published public var isLoadingLocal: Bool = false
    
    @Published public var remotePath: String = ""
    @Published public var remoteHomePath: String = ""
    @Published public var remoteFiles: [FileItem] = []
    @Published public var selectedRemotePath: String?
    @Published public var isLoadingRemote: Bool = false
    
    // MARK: - Transfers & Progress (Requirement 8)
    @Published public var activeTransfer: TransferProgress?
    public let transferState = TransferState()
    private var currentTransferTask: Task<Void, Never>?
    
    // MARK: - Remote Copy (Requirement 5)
    @Published public var isShowingRemoteCopySheet: Bool = false
    @Published public var remoteCopySourceItem: FileItem?
    @Published public var remoteCopyDestinationPath: String = ""
    @Published public var isPerformingRemoteCopy: Bool = false
    
    // MARK: - Deletion Confirmation
    @Published public var itemToDelete: FileItem?
    @Published public var isShowingDeleteConfirmation: Bool = false
    
    // MARK: - Notifications / Toasts
    @Published public var activeToast: ToastItem?
    
    // MARK: - Sudo Session & Password State
    @Published public var isShowingSudoPrompt: Bool = false
    @Published public var sudoPromptPasswordInput: String = ""
    @Published public var sudoPromptTitle: String = "Autenticación Sudo"
    @Published public var sudoPromptMessage: String = "Ingresa la contraseña de sudo para el servidor"
    public var sessionSudoPassword: String?
    private var pendingSudoAction: (() -> Void)?
    
    // MARK: - Favorites (Local & Remote)
    @Published public var localFavorites: [String] = []
    @Published public var remoteFavorites: [String] = []
    
    private let localFavoritesKey = "MacSCP_LocalFavorites"
    private var remoteFavoritesKey: String {
        if let conn = currentConnection {
            return "MacSCP_RemoteFavorites_\(conn.alias)"
        }
        return "MacSCP_RemoteFavorites_Default"
    }
    
    // MARK: - Column Sorting State & Persistence (Requirement: recordar ordenamiento por conexión)
    @Published public var localSortColumn: SortColumn = .name
    @Published public var localSortDirection: SortDirection = .ascending
    
    @Published public var remoteSortColumn: SortColumn = .name
    @Published public var remoteSortDirection: SortDirection = .ascending
    
    private let localSortColumnKey = "MacSCP_LocalSortColumn"
    private let localSortDirectionKey = "MacSCP_LocalSortDirection"
    
    private func remoteSortColumnKey(for alias: String) -> String {
        return "MacSCP_RemoteSortColumn_\(alias)"
    }
    
    private func remoteSortDirectionKey(for alias: String) -> String {
        return "MacSCP_RemoteSortDirection_\(alias)"
    }
    
    // MARK: - Services
    public let sftpClient = SFTPClient()
    public let fileWatchService = FileWatchService.shared
    public let localManager = LocalFileManager.shared
    
    public init() {
        self.localPath = localManager.homePath
        loadSavedConnections()
        loadLocalFiles()
        loadFavorites()
        loadSortSettings()
        setupWatchServiceCallback()
    }
    
    // Filtered SSH connections based on search text
    public var filteredConnections: [SSHConnection] {
        if connectionSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return connections
        }
        let query = connectionSearchText.lowercased()
        return connections.filter {
            $0.alias.lowercased().contains(query) ||
            $0.hostName.lowercased().contains(query) ||
            $0.user.lowercased().contains(query)
        }
    }
    
    // MARK: - SSH Connection Operations (Requirement 1)
    
    public func loadSavedConnections() {
        let loaded = SSHConfigParser.loadConnections()
        self.connections = loaded
    }
    
    public func connect(to connection: SSHConnection) {
        guard !isConnecting else { return }
        isConnecting = true
        
        Task {
            do {
                let resolvedHome = try await sftpClient.connect(connection: connection)
                let cleanHome = resolvedHome.replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
                self.currentConnection = connection
                self.remoteHomePath = cleanHome
                self.remotePath = cleanHome
                self.loadRemoteFavorites()
                self.loadRemoteSortSettings()
                self.isConnecting = false
                self.isShowingConnectionsSheet = false
                self.showToast("Conectado a \(connection.alias)", type: .success)
                
                await self.loadRemoteFiles()
            } catch {
                self.isConnecting = false
                self.showToast("Error conectando a \(connection.alias): \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    public func connectWithSudo(to connection: SSHConnection) {
        var sudoConn = connection
        sudoConn.useSudoSFTP = true
        connect(to: sudoConn)
    }
    
    public var isSessionElevatedWithSudo: Bool {
        return currentConnection?.useSudoSFTP == true
    }
    
    public func promptForSudoPassword(title: String, message: String, action: @escaping () -> Void) {
        self.sudoPromptTitle = title
        self.sudoPromptMessage = message
        self.sudoPromptPasswordInput = ""
        self.pendingSudoAction = action
        self.isShowingSudoPrompt = true
    }
    
    public func submitSudoPassword() {
        self.sessionSudoPassword = sudoPromptPasswordInput
        self.isShowingSudoPrompt = false
        self.sudoPromptPasswordInput = ""
        let action = self.pendingSudoAction
        self.pendingSudoAction = nil
        action?()
    }
    
    public func cancelSudoPassword() {
        self.isShowingSudoPrompt = false
        self.sudoPromptPasswordInput = ""
        self.pendingSudoAction = nil
    }
    
    public func disconnect() {
        Task {
            await sftpClient.disconnect()
            fileWatchService.clearAll()
            self.currentConnection = nil
            self.remoteFiles = []
            self.remotePath = ""
            self.remoteHomePath = ""
            self.remoteFavorites = []
            self.selectedRemotePath = nil
            self.sessionSudoPassword = nil
            self.isShowingSudoPrompt = false
            self.showToast("Desconectado", type: .info)
        }
    }
    
    // MARK: - Local File Navigation (Requirement 2 & 7)
    
    public func loadLocalFiles() {
        isLoadingLocal = true
        do {
            self.localFiles = try localManager.listDirectory(at: localPath)
        } catch {
            showToast("Error listando directorio local: \(error.localizedDescription)", type: .error)
            self.localFiles = []
        }
        isLoadingLocal = false
    }
    
    public func navigateLocal(to path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("La ruta local no puede estar vacía", type: .error)
            return
        }
        
        var expanded = NSString(string: trimmed).expandingTildeInPath
        if !expanded.hasPrefix("/") {
            // Relative to current localPath
            expanded = (localPath as NSString).appendingPathComponent(expanded)
        }
        let cleanPath = (expanded as NSString).standardizingPath
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cleanPath, isDirectory: &isDir) else {
            showToast("La ruta no existe: \(cleanPath)", type: .error)
            return
        }
        guard isDir.boolValue else {
            showToast("La ruta no es un directorio: \(cleanPath)", type: .error)
            return
        }
        
        isLoadingLocal = true
        do {
            let items = try localManager.listDirectory(at: cleanPath)
            self.localPath = cleanPath
            self.localFiles = items
            self.selectedLocalPath = nil
        } catch {
            showToast("Error al acceder a la ruta: \(error.localizedDescription)", type: .error)
        }
        isLoadingLocal = false
    }
    
    public func navigateLocalUp() {
        let parent = localManager.parentPath(of: localPath)
        navigateLocal(to: parent)
    }
    
    public func handleLocalItemDoubleClick(_ item: FileItem) {
        if item.isParentDirectory {
            navigateLocalUp()
            return
        }
        if item.isDirectory {
            navigateLocal(to: item.path)
        } else {
            // Open local file with default editor
            NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }
    
    // MARK: - Remote File Navigation (Requirement 2 & 7)
    
    public func loadRemoteFiles() async {
        guard currentConnection != nil else { return }
        let currentClean = standardizeRemotePath(remotePath)
        isLoadingRemote = true
        do {
            var items = try await sftpClient.listDirectory(path: currentClean)
            
            // Add single canonical ".." entry if not at root "/"
            if currentClean != "/" {
                let parent = (currentClean as NSString).deletingLastPathComponent
                let parentPath = parent.isEmpty ? "/" : parent
                let parentItem = FileItem(
                    name: "..",
                    path: standardizeRemotePath(parentPath),
                    isDirectory: true,
                    isParentDirectory: true,
                    size: 0,
                    isRemote: true
                )
                items.insert(parentItem, at: 0)
            }
            
            self.remotePath = currentClean
            self.remoteFiles = items
        } catch {
            showToast("Error listando archivos remotos: \(error.localizedDescription)", type: .error)
        }
        isLoadingRemote = false
    }
    
    /// Standardizes a Unix path by resolving "." and ".." components and multiple consecutive slashes.
    public func standardizeRemotePath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [String] = []
        for comp in components {
            if comp == "." {
                continue
            } else if comp == ".." {
                if !stack.isEmpty {
                    stack.removeLast()
                }
            } else {
                stack.append(String(comp))
            }
        }
        return "/" + stack.joined(separator: "/")
    }
    
    public func navigateRemote(to path: String) {
        guard currentConnection != nil else {
            showToast("Debes conectarte a un servidor primero", type: .error)
            return
        }
        
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("La ruta remota no puede estar vacía", type: .error)
            return
        }
        
        var target = trimmed
        if target == "~" {
            target = remoteHomePath.isEmpty ? "." : remoteHomePath
        } else if target.hasPrefix("~/") {
            let relativePart = String(target.dropFirst(2))
            if !remoteHomePath.isEmpty {
                target = remoteHomePath == "/" ? "/\(relativePart)" : "\(remoteHomePath)/\(relativePart)"
            }
        } else if !target.hasPrefix("/") {
            // Relative path to current remotePath
            let base = remotePath.isEmpty ? "/" : remotePath
            target = base == "/" ? "/\(target)" : "\(base)/\(target)"
        }
        
        let destination = standardizeRemotePath(target)
        isLoadingRemote = true
        
        Task {
            do {
                var items = try await sftpClient.listDirectory(path: destination)
                
                // Add single canonical ".." entry if not at root "/"
                if destination != "/" {
                    let parent = (destination as NSString).deletingLastPathComponent
                    let parentPath = parent.isEmpty ? "/" : parent
                    let parentItem = FileItem(
                        name: "..",
                        path: standardizeRemotePath(parentPath),
                        isDirectory: true,
                        isParentDirectory: true,
                        size: 0,
                        isRemote: true
                    )
                    items.insert(parentItem, at: 0)
                }
                
                self.remotePath = destination
                self.remoteFiles = items
                self.selectedRemotePath = nil
                self.isLoadingRemote = false
            } catch {
                self.isLoadingRemote = false
                self.showToast("Ruta remota no válida: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    public func navigateRemoteUp() {
        let current = standardizeRemotePath(remotePath)
        guard current != "/" else { return }
        let parent = (current as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        navigateRemote(to: target)
    }
    
    public func handleRemoteItemDoubleClick(_ item: FileItem) {
        if item.isParentDirectory {
            navigateRemoteUp()
            return
        }
        if item.isDirectory {
            navigateRemote(to: item.path)
        } else {
            // Requirement 3: Open in Nextpad++ and auto-upload on save!
            editRemoteFileInNextpad(item: item)
        }
    }
    
    // MARK: - Nextpad++ Integration & Auto-Sync (Requirement 3 + Sudo Mode)
    
    public func editRemoteFileInNextpad(item: FileItem, withSudo: Bool = false) {
        guard let connection = currentConnection else { return }
        
        let localCache = fileWatchService.localCacheURL(
            for: item.path,
            connectionAlias: connection.alias
        )
        
        let prefix = withSudo ? " con sudo 🛡️" : ""
        showToast("Descargando \(item.name) para editar\(prefix)...", type: .info)
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                if withSudo {
                    let data = try await self.sftpClient.executeSudoRead(
                        remotePath: item.path,
                        connection: connection,
                        password: self.sessionSudoPassword
                    )
                    try data.write(to: localCache, options: .atomic)
                } else {
                    try await self.sftpClient.downloadFile(
                        remotePath: item.path,
                        to: localCache
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                    self.activeTransfer = nil
                }
                
                // Open and start watching
                self.fileWatchService.openAndWatch(
                    localURL: localCache,
                    remotePath: item.path,
                    connectionAlias: connection.alias,
                    isElevated: withSudo
                )
                
                self.showToast("Abierto en Nextpad++\(prefix) (se guardará automáticamente al salvar)", type: .success)
            } catch let sftpError as SFTPError {
                self.activeTransfer = nil
                if case .permissionDenied = sftpError, withSudo {
                    self.promptForSudoPassword(
                        title: "Acceso Sudo en \(connection.alias)",
                        message: "Se requiere contraseña de sudo para abrir \(item.name)."
                    ) { [weak self] in
                        self?.editRemoteFileInNextpad(item: item, withSudo: true)
                    }
                } else {
                    self.showToast("Error al abrir archivo\(prefix): \(sftpError.localizedDescription)", type: .error)
                }
            } catch {
                self.activeTransfer = nil
                self.showToast("Error al abrir archivo\(prefix): \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    private func setupWatchServiceCallback() {
        fileWatchService.onFileSaved = { [weak self] monitoredFile in
            guard let self = self else { return }
            self.handleMonitoredFileSaved(monitoredFile)
        }
    }
    
    private func handleMonitoredFileSaved(_ monitoredFile: MonitoredFile) {
        guard let currentConn = currentConnection, currentConn.alias == monitoredFile.connectionAlias else { return }
        
        let fileName = (monitoredFile.remotePath as NSString).lastPathComponent
        let prefix = monitoredFile.isElevated ? " con sudo 🛡️" : ""
        showToast("Sincronizando cambios de \(fileName)\(prefix) con el servidor...", type: .info)
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                if monitoredFile.isElevated {
                    let fileData = try Data(contentsOf: monitoredFile.localURL)
                    try await self.sftpClient.executeSudoWrite(
                        remotePath: monitoredFile.remotePath,
                        data: fileData,
                        connection: currentConn,
                        password: self.sessionSudoPassword
                    )
                    self.showToast("✓ \(fileName) guardado con sudo en el servidor 🛡️", type: .success)
                } else {
                    try await self.sftpClient.uploadFile(
                        localURL: monitoredFile.localURL,
                        to: monitoredFile.remotePath
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                    self.activeTransfer = nil
                    self.showToast("✓ \(fileName) actualizado en el servidor", type: .success)
                }
                
                // Refresh remote directory if currently viewing that folder
                let parent = (monitoredFile.remotePath as NSString).deletingLastPathComponent
                if parent == self.remotePath || (parent.isEmpty && self.remotePath == "/") {
                    await self.loadRemoteFiles()
                }
            } catch let sftpError as SFTPError {
                self.activeTransfer = nil
                if case .permissionDenied = sftpError, monitoredFile.isElevated {
                    self.promptForSudoPassword(
                        title: "Guardar con Sudo en \(currentConn.alias)",
                        message: "Se requiere contraseña de sudo para guardar cambios en \(fileName)."
                    ) { [weak self] in
                        self?.handleMonitoredFileSaved(monitoredFile)
                    }
                } else {
                    self.showToast("Error al sincronizar \(fileName): \(sftpError.localizedDescription)", type: .error)
                }
            } catch {
                self.activeTransfer = nil
                self.showToast("Error al sincronizar \(fileName): \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    // MARK: - Quick File Transfers (Requirement 4 & 8)
    
    /// Quick upload selected local item to current remote folder.
    public func uploadSelectedLocalToRemote() {
        guard currentConnection != nil else {
            showToast("Debes conectarte a un servidor primero", type: .error)
            return
        }
        guard let localPathSelected = selectedLocalPath,
              let item = localFiles.first(where: { $0.path == localPathSelected && !$0.isParentDirectory }) else {
            showToast("Selecciona un archivo local para subir", type: .info)
            return
        }
        
        uploadLocalItem(item)
    }
    
    public func uploadLocalItem(_ item: FileItem) {
        guard currentConnection != nil, !item.isParentDirectory else { return }
        let targetRemotePath = remotePath == "/" ? "/\(item.name)" : "\(remotePath)/\(item.name)"
        let localURL = URL(fileURLWithPath: item.path)
        let isDir = item.isDirectory
        let label = isDir ? "carpeta" : "archivo"
        
        showToast("Subiendo \(label) \(item.name)...", type: .info)
        
        // Reset transfer state
        transferState.reset()
        
        currentTransferTask?.cancel()
        currentTransferTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                if isDir {
                    try await self.sftpClient.uploadDirectory(
                        localURL: localURL,
                        to: targetRemotePath,
                        transferState: self.transferState
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                } else {
                    try await self.sftpClient.uploadFile(
                        localURL: localURL,
                        to: targetRemotePath,
                        transferState: self.transferState
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                }
                
                self.activeTransfer = nil
                self.currentTransferTask = nil
                self.showToast("✓ \(item.name) subido correctamente", type: .success)
                await self.loadRemoteFiles()
            } catch is CancellationError {
                self.activeTransfer = nil
                self.currentTransferTask = nil
                self.showToast("Carga cancelada", type: .info)
            } catch {
                self.activeTransfer = nil
                self.currentTransferTask = nil
                if !Task.isCancelled {
                    self.showToast("Error al subir \(label): \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    /// Quick download selected remote item to current local folder.
    public func downloadSelectedRemoteToLocal() {
        guard let remotePathSelected = selectedRemotePath,
              let item = remoteFiles.first(where: { $0.path == remotePathSelected && !$0.isParentDirectory }) else {
            showToast("Selecciona un elemento remoto para descargar", type: .info)
            return
        }
        
        downloadRemoteItem(item)
    }
    
    public func downloadRemoteItem(_ item: FileItem) {
        guard !item.isParentDirectory else { return }
        let targetLocalURL = URL(fileURLWithPath: localPath).appendingPathComponent(item.name)
        let isDir = item.isDirectory
        let label = isDir ? "carpeta" : "archivo"
        
        showToast("Descargando \(label) \(item.name)...", type: .info)
        
        // Reset transfer state
        transferState.reset()
        
        currentTransferTask?.cancel()
        currentTransferTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                if isDir {
                    try await self.sftpClient.downloadDirectory(
                        remotePath: item.path,
                        to: targetLocalURL,
                        transferState: self.transferState
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                } else {
                    try await self.sftpClient.downloadFile(
                        remotePath: item.path,
                        to: targetLocalURL,
                        transferState: self.transferState
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.activeTransfer = progress
                        }
                    }
                }
                
                self.activeTransfer = nil
                self.currentTransferTask = nil
                self.showToast("✓ \(item.name) descargado correctamente", type: .success)
                self.loadLocalFiles()
            } catch is CancellationError {
                self.activeTransfer = nil
                self.currentTransferTask = nil
                self.showToast("Descarga cancelada", type: .info)
            } catch {
                self.activeTransfer = nil
                self.currentTransferTask = nil
                if !Task.isCancelled {
                    self.showToast("Error al descargar \(label): \(error.localizedDescription)", type: .error)
                }
            }
        }
    }
    
    // MARK: - Transfer Controls (Pause / Resume / Cancel)
    public func pauseTransfer() {
        transferState.pause()
        if var transfer = activeTransfer {
            transfer.isPaused = true
            transfer.currentSpeedBytesPerSec = 0
            activeTransfer = transfer
        }
    }
    
    public func resumeTransfer() {
        transferState.resume()
        if var transfer = activeTransfer {
            transfer.isPaused = false
            activeTransfer = transfer
        }
    }
    
    public func cancelTransfer() {
        transferState.cancel()
        currentTransferTask?.cancel()
        currentTransferTask = nil
        activeTransfer = nil
        showToast("Transferencia cancelada", type: .info)
    }
    
    // MARK: - Delete Operations (Local & Remote)
    
    public func confirmDelete(item: FileItem) {
        guard !item.isParentDirectory else { return }
        self.itemToDelete = item
        self.isShowingDeleteConfirmation = true
    }
    
    public func executeDelete() {
        guard let item = itemToDelete else { return }
        self.itemToDelete = nil
        self.isShowingDeleteConfirmation = false
        
        if item.isRemote {
            deleteRemoteItem(item)
        } else {
            deleteLocalItem(item)
        }
    }
    
    public func deleteLocalItem(_ item: FileItem) {
        guard !item.isParentDirectory else { return }
        let label = item.isDirectory ? "carpeta" : "archivo"
        do {
            try localManager.deleteItem(at: item.path)
            showToast("✓ \(item.name) eliminado", type: .info)
            loadLocalFiles()
        } catch {
            showToast("Error al eliminar \(label) local: \(error.localizedDescription)", type: .error)
        }
    }
    
    public func deleteRemoteItem(_ item: FileItem) {
        guard currentConnection != nil, !item.isParentDirectory else { return }
        let label = item.isDirectory ? "carpeta" : "archivo"
        showToast("Eliminando \(label) \(item.name)...", type: .info)
        
        Task {
            do {
                try await sftpClient.deleteItem(path: item.path, isDirectory: item.isDirectory)
                self.showToast("✓ \(item.name) eliminado del servidor", type: .info)
                await self.loadRemoteFiles()
            } catch {
                self.showToast("Error al eliminar \(label) remoto: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    // MARK: - Remote-to-Remote Quick Copy (Requirement 5)
    
    public func promptRemoteCopy(for item: FileItem) {
        self.remoteCopySourceItem = item
        // Pre-fill destination path with a convenient default
        let ext = (item.name as NSString).pathExtension
        let baseName = (item.name as NSString).deletingPathExtension
        let copyName = ext.isEmpty ? "\(baseName)_copia" : "\(baseName)_copia.\(ext)"
        let destDefault = remotePath == "/" ? "/\(copyName)" : "\(remotePath)/\(copyName)"
        
        self.remoteCopyDestinationPath = destDefault
        self.isShowingRemoteCopySheet = true
    }
    
    public func executeRemoteCopy() {
        guard let source = remoteCopySourceItem, !remoteCopyDestinationPath.isEmpty else { return }
        let dest = remoteCopyDestinationPath
        
        isPerformingRemoteCopy = true
        showToast("Copiando en servidor...", type: .info)
        
        Task {
            do {
                try await sftpClient.remoteCopy(sourcePath: source.path, destPath: dest)
                self.isPerformingRemoteCopy = false
                self.isShowingRemoteCopySheet = false
                self.showToast("✓ Copiado en servidor a \(dest)", type: .success)
                await self.loadRemoteFiles()
            } catch {
                self.isPerformingRemoteCopy = false
                self.showToast("Error al copiar en servidor: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    // MARK: - Clipboard (Requirement 7)
    
    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("Ruta copiada al portapapeles", type: .info)
    }
    
    // MARK: - Toast Notification Helper
    
    public func showToast(_ message: String, type: ToastType) {
        withAnimation {
            self.activeToast = ToastItem(message: message, type: type)
        }
        
        // Auto-dismiss after 3.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self = self else { return }
            if self.activeToast?.message == message {
                withAnimation {
                    self.activeToast = nil
                }
            }
        }
    }
    
    // MARK: - Favorites Management (Requirement: favoritos de rutas)
    
    public func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: localFavoritesKey), !saved.isEmpty {
            self.localFavorites = saved
        } else {
            var defaults: [String] = [localManager.homePath]
            let downloads = "\(localManager.homePath)/Downloads"
            if FileManager.default.fileExists(atPath: downloads) { defaults.append(downloads) }
            let documents = "\(localManager.homePath)/Documents"
            if FileManager.default.fileExists(atPath: documents) { defaults.append(documents) }
            let desktop = "\(localManager.homePath)/Desktop"
            if FileManager.default.fileExists(atPath: desktop) { defaults.append(desktop) }
            self.localFavorites = defaults
            UserDefaults.standard.set(defaults, forKey: localFavoritesKey)
        }
        loadRemoteFavorites()
    }
    
    public func loadRemoteFavorites() {
        guard currentConnection != nil else {
            self.remoteFavorites = []
            return
        }
        if let saved = UserDefaults.standard.stringArray(forKey: remoteFavoritesKey), !saved.isEmpty {
            self.remoteFavorites = saved
        } else {
            if !remoteHomePath.isEmpty {
                self.remoteFavorites = [remoteHomePath]
                UserDefaults.standard.set(self.remoteFavorites, forKey: remoteFavoritesKey)
            } else {
                self.remoteFavorites = []
            }
        }
    }
    
    public func toggleLocalFavorite(_ path: String) {
        let clean = (path as NSString).standardizingPath
        if let index = localFavorites.firstIndex(of: clean) {
            localFavorites.remove(at: index)
            UserDefaults.standard.set(localFavorites, forKey: localFavoritesKey)
            showToast("Ruta eliminada de favoritos", type: .info)
        } else {
            localFavorites.append(clean)
            UserDefaults.standard.set(localFavorites, forKey: localFavoritesKey)
            showToast("Ruta agregada a favoritos", type: .success)
        }
    }
    
    public func removeLocalFavorite(_ path: String) {
        let clean = (path as NSString).standardizingPath
        if let index = localFavorites.firstIndex(of: clean) {
            localFavorites.remove(at: index)
            UserDefaults.standard.set(localFavorites, forKey: localFavoritesKey)
            showToast("Ruta eliminada de favoritos", type: .info)
        }
    }
    
    public func toggleRemoteFavorite(_ path: String) {
        let clean = standardizeRemotePath(path)
        if let index = remoteFavorites.firstIndex(of: clean) {
            remoteFavorites.remove(at: index)
            UserDefaults.standard.set(remoteFavorites, forKey: remoteFavoritesKey)
            showToast("Ruta eliminada de favoritos", type: .info)
        } else {
            remoteFavorites.append(clean)
            UserDefaults.standard.set(remoteFavorites, forKey: remoteFavoritesKey)
            showToast("Ruta agregada a favoritos", type: .success)
        }
    }
    
    public func removeRemoteFavorite(_ path: String) {
        let clean = standardizeRemotePath(path)
        if let index = remoteFavorites.firstIndex(of: clean) {
            remoteFavorites.remove(at: index)
            UserDefaults.standard.set(remoteFavorites, forKey: remoteFavoritesKey)
            showToast("Ruta eliminada de favoritos", type: .info)
        }
    }
    
    // MARK: - Column Sorting Persistence (Requirement: recordar ordenamiento por conexión)
    
    public func loadSortSettings() {
        if let colStr = UserDefaults.standard.string(forKey: localSortColumnKey),
           let col = SortColumn(rawValue: colStr) {
            self.localSortColumn = col
        }
        if let dirStr = UserDefaults.standard.string(forKey: localSortDirectionKey),
           let dir = SortDirection(rawValue: dirStr) {
            self.localSortDirection = dir
        }
        loadRemoteSortSettings()
    }
    
    public func loadRemoteSortSettings() {
        guard let conn = currentConnection else {
            self.remoteSortColumn = .name
            self.remoteSortDirection = .ascending
            return
        }
        if let colStr = UserDefaults.standard.string(forKey: remoteSortColumnKey(for: conn.alias)),
           let col = SortColumn(rawValue: colStr) {
            self.remoteSortColumn = col
        } else {
            self.remoteSortColumn = .name
        }
        if let dirStr = UserDefaults.standard.string(forKey: remoteSortDirectionKey(for: conn.alias)),
           let dir = SortDirection(rawValue: dirStr) {
            self.remoteSortDirection = dir
        } else {
            self.remoteSortDirection = .ascending
        }
    }
    
    public func setLocalSort(column: SortColumn, direction: SortDirection) {
        self.localSortColumn = column
        self.localSortDirection = direction
        UserDefaults.standard.set(column.rawValue, forKey: localSortColumnKey)
        UserDefaults.standard.set(direction.rawValue, forKey: localSortDirectionKey)
    }
    
    public func setRemoteSort(column: SortColumn, direction: SortDirection) {
        self.remoteSortColumn = column
        self.remoteSortDirection = direction
        if let conn = currentConnection {
            UserDefaults.standard.set(column.rawValue, forKey: remoteSortColumnKey(for: conn.alias))
            UserDefaults.standard.set(direction.rawValue, forKey: remoteSortDirectionKey(for: conn.alias))
        }
    }
}

