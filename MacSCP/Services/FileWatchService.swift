import AppKit
import CryptoKit
import Foundation

/// Represents an active file being edited in Nextpad++ with auto-sync to remote server.
public final class MonitoredFile: Identifiable {
    public let id = UUID()
    public let localURL: URL
    public let remotePath: String
    public let connectionAlias: String
    /// The tab that opened this file. Its changes are uploaded through that tab's connection.
    public let ownerID: UUID
    public var lastModifiedDate: Date
    public var isUploading = false
    public let isElevated: Bool
    
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    
    public init(
        localURL: URL,
        remotePath: String,
        connectionAlias: String,
        ownerID: UUID,
        initialDate: Date,
        isElevated: Bool = false
    ) {
        self.localURL = localURL
        self.remotePath = remotePath
        self.connectionAlias = connectionAlias
        self.ownerID = ownerID
        self.lastModifiedDate = initialDate
        self.isElevated = isElevated
    }
    
    public func startMonitoring(onChange: @escaping () -> Void) {
        let fd = open(localURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        
        source.setEventHandler {
            onChange()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        self.dispatchSource = source
        source.resume()
    }
    
    public func stopMonitoring() {
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
    
    deinit {
        stopMonitoring()
    }
}

/// Service managing remote files opened in Nextpad++ and auto-uploading on save.
@MainActor
public final class FileWatchService: ObservableObject {
    public static let shared = FileWatchService()
    
    @Published public var monitoredFiles: [MonitoredFile] = []
    @Published public var lastSyncMessage: String?
    
    private var pollTimer: Timer?
    private var pendingUploadWorkItem: [UUID: DispatchWorkItem] = [:]
    private var fileSavedHandlers: [UUID: (_ file: MonitoredFile) -> Void] = [:]
    
    private init() {
        startPollingTimer()
    }
    
    /// Registers the code that uploads saved files opened by the tab `ownerID`.
    public func setFileSavedHandler(ownerID: UUID, handler: @escaping (_ file: MonitoredFile) -> Void) {
        fileSavedHandlers[ownerID] = handler
    }
    
    public func removeFileSavedHandler(ownerID: UUID) {
        fileSavedHandlers[ownerID] = nil
    }
    
    private var remoteEditCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacSCP", isDirectory: true)
            .appendingPathComponent("RemoteEdit", isDirectory: true)
    }
    
    /// Stops all watching and deletes every local copy of a remote file. Called when the app quits.
    public func removeAllLocalCopies() {
        for file in monitoredFiles {
            file.stopMonitoring()
        }
        monitoredFiles.removeAll()
        try? FileManager.default.removeItem(at: remoteEditCacheURL)
    }
    
    /// Prepares local cache directory for the remote file.
    /// Each server and remote folder gets its own directory, so files with the same name
    /// never share a local copy. The file keeps its name for the editor's title bar.
    public func localCacheURL(for remotePath: String, connection: SSHConnection) -> URL {
        let remoteFolder = (remotePath as NSString).deletingLastPathComponent
        let digest = SHA256.hash(data: Data("\(connection.destinationString):\(connection.port):\(remoteFolder)".utf8))
        let folderKey = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let dir = remoteEditCacheURL
            .appendingPathComponent(connection.alias, isDirectory: true)
            .appendingPathComponent(folderKey, isDirectory: true)
        
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let fileName = (remotePath as NSString).lastPathComponent
        return dir.appendingPathComponent(fileName)
    }
    
    /// Opens the downloaded file in Nextpad++ and starts monitoring for changes.
    public func openAndWatch(
        localURL: URL,
        remotePath: String,
        connectionAlias: String,
        ownerID: UUID,
        isElevated: Bool = false
    ) {
        // Stop any existing monitor for this exact file
        removeMonitor(for: remotePath, ownerID: ownerID)
        
        let modDate = (try? localURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let monitored = MonitoredFile(
            localURL: localURL,
            remotePath: remotePath,
            connectionAlias: connectionAlias,
            ownerID: ownerID,
            initialDate: modDate,
            isElevated: isElevated
        )
        
        monitored.startMonitoring { [weak self, weak monitored] in
            guard let self = self, let monitored = monitored else { return }
            self.handlePotentialFileModification(monitored: monitored)
        }
        
        monitoredFiles.append(monitored)
        
        // Launch Nextpad++
        openInNextpad(fileURL: localURL)
    }
    
    /// Records that a fresh download replaced the local copy, so it isn't taken for a user's save.
    public func markLocalCopyRefreshed(at localURL: URL) {
        guard let date = try? localURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return
        }
        for monitored in monitoredFiles where monitored.localURL == localURL {
            monitored.lastModifiedDate = date
        }
    }
    
    /// Launches Nextpad++.app with the specified file URL.
    public func openInNextpad(fileURL: URL) {
        let bundleID = "org.nextpadplusplus.mac"
        let fallbackPath = "/Applications/Nextpad++.app"
        
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    print("Error opening Nextpad++ via bundle ID: \(error.localizedDescription)")
                }
            }
        } else if FileManager.default.fileExists(atPath: fallbackPath) {
            let appURL = URL(fileURLWithPath: fallbackPath)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    print("Error opening Nextpad++ via path: \(error.localizedDescription)")
                }
            }
        } else {
            // Fallback to system default text editor if Nextpad++ is not installed
            NSWorkspace.shared.open(fileURL)
        }
    }
    
    /// Handles file modification detection, debounces, and triggers auto-upload.
    private func handlePotentialFileModification(monitored: MonitoredFile) {
        guard let currentDate = try? monitored.localURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return
        }
        
        // If file modified timestamp hasn't progressed, skip
        guard currentDate > monitored.lastModifiedDate else {
            return
        }
        
        monitored.lastModifiedDate = currentDate
        
        // Tabs on the same server can share a local copy, and one save needs only one upload.
        guard monitoredFiles.first(where: { $0.localURL == monitored.localURL }) === monitored else {
            return
        }
        
        // Debounce by 400ms to allow editor to finish disk write
        pendingUploadWorkItem[monitored.id]?.cancel()
        
        let workItem = DispatchWorkItem { [weak self, weak monitored] in
            guard let self = self, let monitored = monitored else { return }
            self.fileSavedHandlers[monitored.ownerID]?(monitored)
        }
        
        pendingUploadWorkItem[monitored.id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }
    
    /// Background polling timer as a secondary safeguard against atomic-swap saves.
    private func startPollingTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for monitored in self.monitoredFiles {
                    self.handlePotentialFileModification(monitored: monitored)
                }
            }
        }
    }
    
    public func removeMonitor(for remotePath: String, ownerID: UUID) {
        if let idx = monitoredFiles.firstIndex(where: { $0.remotePath == remotePath && $0.ownerID == ownerID }) {
            monitoredFiles[idx].stopMonitoring()
            monitoredFiles.remove(at: idx)
        }
    }
    
    /// Stops watching the files opened by one tab, leaving other tabs' files alone.
    public func clearMonitors(ownerID: UUID) {
        for file in monitoredFiles where file.ownerID == ownerID {
            file.stopMonitoring()
        }
        monitoredFiles.removeAll { $0.ownerID == ownerID }
    }
}
