import Foundation

public enum SFTPError: LocalizedError {
    case connectionFailed(String)
    case handshakeFailed
    case protocolError(String)
    case sftpStatusError(code: UInt32, message: String)
    case fileNotFound(String)
    case permissionDenied(String)
    case timeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Error de conexión: \(msg)"
        case .handshakeFailed: return "Fallo en la negociación del protocolo SFTP"
        case .protocolError(let msg): return "Error de protocolo: \(msg)"
        case .sftpStatusError(let code, let msg): return "Error SFTP (\(code)): \(msg)"
        case .fileNotFound(let path): return "No se encontró el archivo: \(path)"
        case .permissionDenied(let path): return "Permiso denegado: \(path)"
        case .timeout: return "Tiempo de espera agotado"
        case .cancelled: return "Operación cancelada"
        }
    }
}

/// Native SFTP v3 Client communicating over OpenSSH subsystem (`/usr/bin/ssh <host> -s sftp`).
/// Leverages macOS's native SSH configuration, keys, agent, and Keychain with zero external dependencies.
public actor SFTPClient {
    private var process: Process?
    private var inPipe: Pipe?
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    
    private var inHandle: FileHandle?
    private var outHandle: FileHandle?
    
    private var requestIdCounter: UInt32 = 1
    private var isConnected = false
    private var activeConnection: SSHConnection?
    
    public init() {}
    
    // MARK: - SFTP Constants
    private let SSH_FXP_INIT: UInt8 = 1
    private let SSH_FXP_VERSION: UInt8 = 2
    private let SSH_FXP_OPEN: UInt8 = 3
    private let SSH_FXP_CLOSE: UInt8 = 4
    private let SSH_FXP_READ: UInt8 = 5
    private let SSH_FXP_WRITE: UInt8 = 6
    private let SSH_FXP_LSTAT: UInt8 = 7
    private let SSH_FXP_FSTAT: UInt8 = 8
    private let SSH_FXP_SETSTAT: UInt8 = 9
    private let SSH_FXP_FSETSTAT: UInt8 = 10
    private let SSH_FXP_OPENDIR: UInt8 = 11
    private let SSH_FXP_READDIR: UInt8 = 12
    private let SSH_FXP_REMOVE: UInt8 = 13
    private let SSH_FXP_MKDIR: UInt8 = 14
    private let SSH_FXP_RMDIR: UInt8 = 15
    private let SSH_FXP_REALPATH: UInt8 = 16
    private let SSH_FXP_STAT: UInt8 = 17
    private let SSH_FXP_RENAME: UInt8 = 18
    
    private let SSH_FXP_STATUS: UInt8 = 101
    private let SSH_FXP_HANDLE: UInt8 = 102
    private let SSH_FXP_DATA: UInt8 = 103
    private let SSH_FXP_NAME: UInt8 = 104
    private let SSH_FXP_ATTRS: UInt8 = 105
    
    // Status codes
    private let SSH_FX_OK: UInt32 = 0
    private let SSH_FX_EOF: UInt32 = 1
    private let SSH_FX_NO_SUCH_FILE: UInt32 = 2
    private let SSH_FX_PERMISSION_DENIED: UInt32 = 3
    
    // Open flags
    private let SSH_FXF_READ: UInt32 = 0x00000001
    private let SSH_FXF_WRITE: UInt32 = 0x00000002
    private let SSH_FXF_APPEND: UInt32 = 0x00000004
    private let SSH_FXF_CREAT: UInt32 = 0x00000008
    private let SSH_FXF_TRUNC: UInt32 = 0x00000010
    private let SSH_FXF_EXCL: UInt32 = 0x00000020
    
    // MARK: - Connection Lifecycle
    
    public func connect(connection: SSHConnection) async throws -> String {
        disconnect()
        
        self.activeConnection = connection
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=15"
        ]
        
        if connection.port != 22 {
            args.append(contentsOf: ["-p", "\(connection.port)"])
        }
        
        if let idFile = connection.identityFile, !idFile.isEmpty {
            let expanded = NSString(string: idFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        
        if let proxy = connection.proxyJump, !proxy.isEmpty {
            args.append(contentsOf: ["-J", proxy])
        }
        
        if connection.useSudoSFTP {
            // Elevated root SFTP session via sudo sftp-server
            args.append(connection.destinationString)
            args.append("sudo -n /usr/libexec/openssh/sftp-server 2>/dev/null || sudo -n /usr/lib/openssh/sftp-server 2>/dev/null || sudo -n sftp-server")
        } else {
            args.append("-s") // Request subsystem
            args.append(connection.destinationString)
            args.append("sftp")
        }
        
        proc.arguments = args
        
        let inP = Pipe()
        let outP = Pipe()
        let errP = Pipe()
        
        proc.standardInput = inP
        proc.standardOutput = outP
        proc.standardError = errP
        
        self.process = proc
        self.inPipe = inP
        self.outPipe = outP
        self.errPipe = errP
        self.inHandle = inP.fileHandleForWriting
        self.outHandle = outP.fileHandleForReading
        
        do {
            try proc.run()
        } catch {
            throw SFTPError.connectionFailed("No se pudo iniciar el proceso ssh: \(error.localizedDescription)")
        }
        
        // Perform SFTP v3 Handshake: Send INIT
        try sendPacket(type: SSH_FXP_INIT, payload: UInt32(3).bigEndianBytes)
        
        // Receive VERSION
        let (respType, _) = try readPacket()
        guard respType == SSH_FXP_VERSION else {
            // Check stderr for ssh connection errors
            let errData = errP.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            disconnect()
            throw SFTPError.connectionFailed("Respuesta inválida del servidor: \(errStr.isEmpty ? "esperaba VERSION (\(SSH_FXP_VERSION)), recibió \(respType)" : errStr)")
        }
        
        self.isConnected = true
        
        // Resolve home directory using REALPATH "."
        let homeDir = (try? realPath(path: ".")) ?? "/"
        return cleanRemotePath(homeDir)
    }
    
    private func cleanRemotePath(_ path: String) -> String {
        var clean = path
        while clean.hasPrefix("//") {
            clean = String(clean.dropFirst())
        }
        return clean.isEmpty ? "/" : clean
    }
    
    public func disconnect() {
        isConnected = false
        activeConnection = nil
        try? inHandle?.close()
        try? outHandle?.close()
        process?.terminate()
        process = nil
        inPipe = nil
        outPipe = nil
        errPipe = nil
        inHandle = nil
        outHandle = nil
    }
    
    // MARK: - Core SFTP Operations
    
    /// Resolves canonical path (e.g. "." -> "/home/user").
    public func realPath(path: String) throws -> String {
        let reqId = nextRequestId()
        var payload = reqId.bigEndianBytes
        payload.append(contentsOf: encodeString(path))
        
        try sendPacket(type: SSH_FXP_REALPATH, payload: payload)
        let (respType, respPayload) = try readPacket()
        
        if respType == SSH_FXP_NAME {
            let names = parseNamePacket(respPayload)
            if let first = names.first {
                return cleanRemotePath(first.path)
            }
        } else if respType == SSH_FXP_STATUS {
            let (code, msg) = parseStatusPacket(respPayload)
            throw SFTPError.sftpStatusError(code: code, message: msg)
        }
        return cleanRemotePath(path)
    }
    
    /// Lists contents of a remote directory.
    public func listDirectory(path: String) throws -> [FileItem] {
        let reqId = nextRequestId()
        var openPayload = reqId.bigEndianBytes
        openPayload.append(contentsOf: encodeString(path))
        
        try sendPacket(type: SSH_FXP_OPENDIR, payload: openPayload)
        let (openRespType, openRespPayload) = try readPacket()
        
        guard openRespType == SSH_FXP_HANDLE else {
            if openRespType == SSH_FXP_STATUS {
                let (code, msg) = parseStatusPacket(openRespPayload)
                if code == SSH_FX_NO_SUCH_FILE {
                    throw SFTPError.fileNotFound(path)
                } else if code == SSH_FX_PERMISSION_DENIED {
                    throw SFTPError.permissionDenied(path)
                }
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
            throw SFTPError.protocolError("Error al abrir directorio: tipo \(openRespType)")
        }
        
        let handle = parseHandle(openRespPayload)
        var items: [FileItem] = []
        
        defer {
            // Close directory handle
            let closeId = nextRequestId()
            var closePayload = closeId.bigEndianBytes
            closePayload.append(contentsOf: encodeData(handle))
            try? sendPacket(type: SSH_FXP_CLOSE, payload: closePayload)
            _ = try? readPacket()
        }
        
        // Read directory entries in loop until EOF
        while true {
            let readId = nextRequestId()
            var readPayload = readId.bigEndianBytes
            readPayload.append(contentsOf: encodeData(handle))
            
            try sendPacket(type: SSH_FXP_READDIR, payload: readPayload)
            let (readRespType, readRespPayload) = try readPacket()
            
            if readRespType == SSH_FXP_NAME {
                let batch = parseNamePacket(readRespPayload, parentPath: path)
                for item in batch {
                    // Filter out "." and ".." directory entries from raw stream
                    if item.name == "." || item.name == ".." { continue }
                    items.append(item)
                }
            } else if readRespType == SSH_FXP_STATUS {
                let (code, _) = parseStatusPacket(readRespPayload)
                if code == SSH_FX_EOF {
                    // Finished reading directory
                    break
                }
                break
            } else {
                break
            }
        }
        
        // Sort: folders first, then alphabetical
        return items.sorted { a, b in
            if a.isParentDirectory { return true }
            if b.isParentDirectory { return false }
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    
    /// Downloads a remote file to a local destination with real-time speed & progress updates.
    public func downloadFile(
        remotePath: String,
        to localURL: URL,
        transferState: TransferState? = nil,
        onProgress: @escaping (TransferProgress) -> Void
    ) async throws {
        // First get remote file size via STAT
        let statSize = (try? await getFileSize(remotePath: remotePath)) ?? 0
        
        let openId = nextRequestId()
        var openPayload = openId.bigEndianBytes
        openPayload.append(contentsOf: encodeString(remotePath))
        openPayload.append(contentsOf: SSH_FXF_READ.bigEndianBytes)
        openPayload.append(contentsOf: UInt32(0).bigEndianBytes) // empty attrs
        
        try sendPacket(type: SSH_FXP_OPEN, payload: openPayload)
        let (openRespType, openRespPayload) = try readPacket()
        
        guard openRespType == SSH_FXP_HANDLE else {
            if openRespType == SSH_FXP_STATUS {
                let (code, msg) = parseStatusPacket(openRespPayload)
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
            throw SFTPError.protocolError("No se pudo abrir el archivo remoto")
        }
        
        let handle = parseHandle(openRespPayload)
        
        defer {
            let closeId = nextRequestId()
            var closePayload = closeId.bigEndianBytes
            closePayload.append(contentsOf: encodeData(handle))
            try? sendPacket(type: SSH_FXP_CLOSE, payload: closePayload)
            _ = try? readPacket()
        }
        
        // Ensure local parent directory exists
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }
        
        var offset: UInt64 = 0
        let chunkSize: UInt32 = 65536 // 64 KB chunks
        let fileName = (remotePath as NSString).lastPathComponent
        
        var lastTime = Date()
        var bytesSinceLastTime: Int64 = 0
        var currentSpeed: Double = 0
        
        while true {
            // Check for cancellation
            if transferState?.isCancelled == true || Task.isCancelled {
                try? FileManager.default.removeItem(at: localURL)
                throw CancellationError()
            }
            
            // Check for pause
            while transferState?.isPaused == true {
                if transferState?.isCancelled == true || Task.isCancelled {
                    try? FileManager.default.removeItem(at: localURL)
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 120_000_000)
            }
            
            let readId = nextRequestId()
            var readPayload = readId.bigEndianBytes
            readPayload.append(contentsOf: encodeData(handle))
            readPayload.append(contentsOf: offset.bigEndianBytes)
            readPayload.append(contentsOf: chunkSize.bigEndianBytes)
            
            try sendPacket(type: SSH_FXP_READ, payload: readPayload)
            let (readType, readPayloadResp) = try readPacket()
            
            if readType == SSH_FXP_DATA {
                let data = parseData(readPayloadResp)
                if data.isEmpty { break }
                
                try fileHandle.write(contentsOf: data)
                offset += UInt64(data.count)
                bytesSinceLastTime += Int64(data.count)
                
                // Speed calculation
                let now = Date()
                let elapsed = now.timeIntervalSince(lastTime)
                if elapsed >= 0.25 {
                    currentSpeed = Double(bytesSinceLastTime) / elapsed
                    bytesSinceLastTime = 0
                    lastTime = now
                    
                    let progress = TransferProgress(
                        fileName: fileName,
                        direction: .download,
                        bytesTransferred: Int64(offset),
                        totalBytes: max(statSize, Int64(offset)),
                        currentSpeedBytesPerSec: (transferState?.isPaused == true) ? 0 : currentSpeed,
                        isCompleted: false,
                        isPaused: transferState?.isPaused ?? false
                    )
                    onProgress(progress)
                }
            } else if readType == SSH_FXP_STATUS {
                let (code, _) = parseStatusPacket(readPayloadResp)
                if code == SSH_FX_EOF {
                    break
                } else {
                    throw SFTPError.sftpStatusError(code: code, message: "Error leyendo datos")
                }
            } else {
                break
            }
        }
        
        // Notify completion
        let finalProgress = TransferProgress(
            fileName: fileName,
            direction: .download,
            bytesTransferred: Int64(offset),
            totalBytes: Int64(offset),
            currentSpeedBytesPerSec: 0,
            isCompleted: true
        )
        onProgress(finalProgress)
    }
    
    /// Uploads a local file to a remote destination with real-time speed & progress updates.
    public func uploadFile(
        localURL: URL,
        to remotePath: String,
        transferState: TransferState? = nil,
        onProgress: @escaping (TransferProgress) -> Void
    ) async throws {
        let fileHandle = try FileHandle(forReadingFrom: localURL)
        defer { try? fileHandle.close() }
        
        let localAttributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let totalSize = (localAttributes[.size] as? Int64) ?? 0
        let fileName = localURL.lastPathComponent
        
        let openId = nextRequestId()
        var openPayload = openId.bigEndianBytes
        openPayload.append(contentsOf: encodeString(remotePath))
        let flags = SSH_FXF_WRITE | SSH_FXF_CREAT | SSH_FXF_TRUNC
        openPayload.append(contentsOf: flags.bigEndianBytes)
        openPayload.append(contentsOf: UInt32(0).bigEndianBytes) // empty attrs
        
        try sendPacket(type: SSH_FXP_OPEN, payload: openPayload)
        let (openRespType, openRespPayload) = try readPacket()
        
        guard openRespType == SSH_FXP_HANDLE else {
            if openRespType == SSH_FXP_STATUS {
                let (code, msg) = parseStatusPacket(openRespPayload)
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
            throw SFTPError.protocolError("No se pudo crear el archivo remoto: \(remotePath)")
        }
        
        let handle = parseHandle(openRespPayload)
        
        defer {
            let closeId = nextRequestId()
            var closePayload = closeId.bigEndianBytes
            closePayload.append(contentsOf: encodeData(handle))
            try? sendPacket(type: SSH_FXP_CLOSE, payload: closePayload)
            _ = try? readPacket()
        }
        
        var offset: UInt64 = 0
        let chunkSize = 65536 // 64 KB
        
        var lastTime = Date()
        var bytesSinceLastTime: Int64 = 0
        var currentSpeed: Double = 0
        
        while true {
            // Check for cancellation
            if transferState?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }
            
            // Check for pause
            while transferState?.isPaused == true {
                if transferState?.isCancelled == true || Task.isCancelled {
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 120_000_000)
            }
            
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            
            let writeId = nextRequestId()
            var writePayload = writeId.bigEndianBytes
            writePayload.append(contentsOf: encodeData(handle))
            writePayload.append(contentsOf: offset.bigEndianBytes)
            writePayload.append(contentsOf: encodeData(chunk))
            
            try sendPacket(type: SSH_FXP_WRITE, payload: writePayload)
            let (writeRespType, writeRespPayload) = try readPacket()
            
            if writeRespType == SSH_FXP_STATUS {
                let (code, msg) = parseStatusPacket(writeRespPayload)
                guard code == SSH_FX_OK else {
                    throw SFTPError.sftpStatusError(code: code, message: msg)
                }
            }
            
            offset += UInt64(chunk.count)
            bytesSinceLastTime += Int64(chunk.count)
            
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 0.25 {
                currentSpeed = Double(bytesSinceLastTime) / elapsed
                bytesSinceLastTime = 0
                lastTime = now
                
                let progress = TransferProgress(
                    fileName: fileName,
                    direction: .upload,
                    bytesTransferred: Int64(offset),
                    totalBytes: totalSize,
                    currentSpeedBytesPerSec: (transferState?.isPaused == true) ? 0 : currentSpeed,
                    isCompleted: false,
                    isPaused: transferState?.isPaused ?? false
                )
                onProgress(progress)
            }
        }
        
        // Notify completion
        let finalProgress = TransferProgress(
            fileName: fileName,
            direction: .upload,
            bytesTransferred: Int64(offset),
            totalBytes: totalSize,
            currentSpeedBytesPerSec: 0,
            isCompleted: true
        )
        onProgress(finalProgress)
    }
    
    /// Remote-to-Remote quick copy (Requirement 5).
    /// Executes `cp -r <source> <dest>` directly on the remote server via SSH.
    public func remoteCopy(sourcePath: String, destPath: String) async throws {
        guard let connection = activeConnection else {
            throw SFTPError.connectionFailed("No hay conexión activa")
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=15"
        ]
        
        if connection.port != 22 {
            args.append(contentsOf: ["-p", "\(connection.port)"])
        }
        if let idFile = connection.identityFile, !idFile.isEmpty {
            let expanded = NSString(string: idFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        if let proxy = connection.proxyJump, !proxy.isEmpty {
            args.append(contentsOf: ["-J", proxy])
        }
        
        args.append(connection.destinationString)
        
        // Escaped command cp -r
        let safeSource = sourcePath.replacingOccurrences(of: "'", with: "'\\''")
        let safeDest = destPath.replacingOccurrences(of: "'", with: "'\\''")
        args.append("cp -r '\(safeSource)' '\(safeDest)'")
        
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        
        try proc.run()
        proc.waitUntilExit()
        
        if proc.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "Error desconocido"
            throw SFTPError.sftpStatusError(code: UInt32(proc.terminationStatus), message: errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    /// Creates a directory on the remote server.
    public func createDirectory(path: String) throws {
        let reqId = nextRequestId()
        var payload = reqId.bigEndianBytes
        payload.append(contentsOf: encodeString(path))
        payload.append(contentsOf: UInt32(0).bigEndianBytes) // default attrs
        
        try sendPacket(type: SSH_FXP_MKDIR, payload: payload)
        let (respType, respPayload) = try readPacket()
        if respType == SSH_FXP_STATUS {
            let (code, msg) = parseStatusPacket(respPayload)
            if code != SSH_FX_OK {
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
        }
    }
    
    /// Deletes a file on the remote server.
    public func deleteFile(path: String) throws {
        let reqId = nextRequestId()
        var payload = reqId.bigEndianBytes
        payload.append(contentsOf: encodeString(path))
        
        try sendPacket(type: SSH_FXP_REMOVE, payload: payload)
        let (respType, respPayload) = try readPacket()
        if respType == SSH_FXP_STATUS {
            let (code, msg) = parseStatusPacket(respPayload)
            if code != SSH_FX_OK {
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
        }
    }
    
    /// Removes an empty directory on the remote server via SSH_FXP_RMDIR.
    public func removeDirectory(path: String) throws {
        let reqId = nextRequestId()
        var payload = reqId.bigEndianBytes
        payload.append(contentsOf: encodeString(path))
        
        try sendPacket(type: SSH_FXP_RMDIR, payload: payload)
        let (respType, respPayload) = try readPacket()
        if respType == SSH_FXP_STATUS {
            let (code, msg) = parseStatusPacket(respPayload)
            if code != SSH_FX_OK {
                throw SFTPError.sftpStatusError(code: code, message: msg)
            }
        }
    }
    
    /// Recursively deletes a remote file or folder.
    public func deleteItem(path: String, isDirectory: Bool) async throws {
        if !isDirectory {
            try deleteFile(path: path)
            return
        }
        
        // List contents and delete recursively
        let items = try listDirectory(path: path)
        for item in items {
            guard !item.isParentDirectory else { continue }
            try await deleteItem(path: item.path, isDirectory: item.isDirectory)
        }
        try removeDirectory(path: path)
    }
    
    /// Uploads an entire directory and its contents recursively to the remote destination.
    public func uploadDirectory(
        localURL: URL,
        to remotePath: String,
        transferState: TransferState? = nil,
        onProgress: @escaping (TransferProgress) -> Void
    ) async throws {
        if transferState?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }
        
        // Create destination directory if needed
        do {
            try createDirectory(path: remotePath)
        } catch {
            // May already exist
        }
        
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: localURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for itemURL in contents {
            if transferState?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }
            
            let subRemotePath = remotePath == "/" ? "/\(itemURL.lastPathComponent)" : "\(remotePath)/\(itemURL.lastPathComponent)"
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isDir {
                try await uploadDirectory(localURL: itemURL, to: subRemotePath, transferState: transferState, onProgress: onProgress)
            } else {
                try await uploadFile(localURL: itemURL, to: subRemotePath, transferState: transferState, onProgress: onProgress)
            }
        }
    }
    
    /// Downloads an entire directory and its contents recursively to a local directory.
    public func downloadDirectory(
        remotePath: String,
        to localURL: URL,
        transferState: TransferState? = nil,
        onProgress: @escaping (TransferProgress) -> Void
    ) async throws {
        if transferState?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: localURL.path) {
            try fileManager.createDirectory(at: localURL, withIntermediateDirectories: true)
        }
        
        let items = try listDirectory(path: remotePath)
        for item in items {
            guard !item.isParentDirectory else { continue }
            if transferState?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }
            
            let targetURL = localURL.appendingPathComponent(item.name)
            if item.isDirectory {
                try await downloadDirectory(remotePath: item.path, to: targetURL, transferState: transferState, onProgress: onProgress)
            } else {
                try await downloadFile(remotePath: item.path, to: targetURL, transferState: transferState, onProgress: onProgress)
            }
        }
    }
    
    // MARK: - Private Protocol Helpers
    
    private func getFileSize(remotePath: String) async throws -> Int64 {
        let reqId = nextRequestId()
        var payload = reqId.bigEndianBytes
        payload.append(contentsOf: encodeString(remotePath))
        
        try sendPacket(type: SSH_FXP_STAT, payload: payload)
        let (respType, respPayload) = try readPacket()
        
        if respType == SSH_FXP_ATTRS {
            return parseAttrsSize(respPayload)
        }
        return 0
    }
    
    private func nextRequestId() -> UInt32 {
        let current = requestIdCounter
        requestIdCounter &+= 1
        return current
    }
    
    private func sendPacket(type: UInt8, payload: Data) throws {
        guard let inHandle = inHandle else { throw SFTPError.connectionFailed("Handle de escritura cerrado") }
        
        let length = UInt32(1 + payload.count)
        var packet = length.bigEndianBytes
        packet.append(type)
        packet.append(payload)
        
        try inHandle.write(contentsOf: packet)
    }
    
    private func readPacket() throws -> (type: UInt8, payload: Data) {
        guard let outHandle = outHandle else { throw SFTPError.connectionFailed("Handle de lectura cerrado") }
        
        let lengthData = try readExact(from: outHandle, count: 4)
        guard let length = lengthData.readUInt32BE(at: 0), length > 0 else {
            throw SFTPError.protocolError("Paquete con longitud 0 o inválida")
        }
        
        let packetData = try readExact(from: outHandle, count: Int(length))
        let type = packetData[0]
        let payload = packetData.dropFirst(1)
        
        return (type, Data(payload))
    }
    
    private func readExact(from handle: FileHandle, count: Int) throws -> Data {
        var accumulated = Data()
        while accumulated.count < count {
            let needed = count - accumulated.count
            let chunk = handle.readData(ofLength: needed)
            if chunk.isEmpty {
                throw SFTPError.connectionFailed("Conexión remota cerrada inesperadamente")
            }
            accumulated.append(chunk)
        }
        return accumulated
    }
    
    // MARK: - Binary Serialization / Deserialization
    
    private func encodeString(_ string: String) -> Data {
        let utf8 = Data(string.utf8)
        var data = UInt32(utf8.count).bigEndianBytes
        data.append(utf8)
        return data
    }
    
    private func encodeData(_ bytes: Data) -> Data {
        var data = UInt32(bytes.count).bigEndianBytes
        data.append(bytes)
        return data
    }
    
    private func parseHandle(_ data: Data) -> Data {
        guard data.count >= 8, let handleLen = data.readUInt32BE(at: 4) else { return Data() }
        let handleBytes = data.dropFirst(8).prefix(Int(handleLen))
        return Data(handleBytes)
    }
    
    private func parseData(_ data: Data) -> Data {
        guard data.count >= 8, let dataLen = data.readUInt32BE(at: 4) else { return Data() }
        let body = data.dropFirst(8).prefix(Int(dataLen))
        return Data(body)
    }
    
    private func parseStatusPacket(_ data: Data) -> (code: UInt32, message: String) {
        guard data.count >= 8, let code = data.readUInt32BE(at: 4) else { return (0, "") }
        
        var message = ""
        if data.count >= 12, let msgLen = data.readUInt32BE(at: 8) {
            let msgLenInt = Int(msgLen)
            if data.count >= 12 + msgLenInt {
                let msgData = data.dropFirst(12).prefix(msgLenInt)
                message = String(data: msgData, encoding: .utf8) ?? ""
            }
        }
        return (code, message)
    }
    
    private func parseAttrsSize(_ data: Data) -> Int64 {
        guard data.count >= 8, let flags = data.readUInt32BE(at: 4) else { return 0 }
        let SSH_FILEXFER_ATTR_SIZE: UInt32 = 0x00000001
        
        if (flags & SSH_FILEXFER_ATTR_SIZE) != 0, let size = data.readUInt64BE(at: 8) {
            return Int64(size)
        }
        return 0
    }
    
    private func parseNamePacket(_ data: Data, parentPath: String = "") -> [FileItem] {
        var items: [FileItem] = []
        guard data.count >= 8 else { return items }
        
        var offset = 4 // Skip reqId
        guard let count = data.readUInt32BE(at: offset) else { return items }
        offset += 4
        
        for _ in 0..<count {
            guard let nameLenU32 = data.readUInt32BE(at: offset) else { break }
            let nameLen = Int(nameLenU32)
            offset += 4
            
            guard offset + nameLen <= data.count else { break }
            let nameData = data.dropFirst(offset).prefix(nameLen)
            let fileName = String(data: nameData, encoding: .utf8) ?? ""
            offset += nameLen
            
            // Long name
            guard let longLenU32 = data.readUInt32BE(at: offset) else { break }
            let longLen = Int(longLenU32)
            offset += 4
            
            var longName = ""
            if offset + longLen <= data.count {
                let longData = data.dropFirst(offset).prefix(longLen)
                longName = String(data: longData, encoding: .utf8) ?? ""
                offset += longLen
            }
            
            // Attributes
            var fileSize: Int64 = 0
            var isDir = false
            var modDate: Date? = nil
            
            if let flags = data.readUInt32BE(at: offset) {
                offset += 4
                
                let ATTR_SIZE: UInt32 = 0x00000001
                let ATTR_UIDGID: UInt32 = 0x00000002
                let ATTR_PERMS: UInt32 = 0x00000004
                let ATTR_ACMODTIME: UInt32 = 0x00000008
                let ATTR_EXTENDED: UInt32 = 0x80000000
                
                if (flags & ATTR_SIZE) != 0 {
                    if let s = data.readUInt64BE(at: offset) {
                        fileSize = Int64(s)
                        offset += 8
                    }
                }
                
                if (flags & ATTR_UIDGID) != 0 {
                    offset += 8 // uid (4) + gid (4)
                }
                
                if (flags & ATTR_PERMS) != 0 {
                    if let perms = data.readUInt32BE(at: offset) {
                        // Check S_IFDIR (0o040000)
                        if (perms & 0o170000) == 0o040000 {
                            isDir = true
                        }
                        offset += 4
                    }
                }
                
                if (flags & ATTR_ACMODTIME) != 0 {
                    if let _ = data.readUInt32BE(at: offset),
                       let mtime = data.readUInt32BE(at: offset + 4) {
                        modDate = Date(timeIntervalSince1970: TimeInterval(mtime))
                        offset += 8
                    }
                }
                
                if (flags & ATTR_EXTENDED) != 0 {
                    if let extCount = data.readUInt32BE(at: offset) {
                        offset += 4
                        for _ in 0..<extCount {
                            if let typeLen = data.readUInt32BE(at: offset) {
                                offset += 4 + Int(typeLen)
                            }
                            if let dataLen = data.readUInt32BE(at: offset) {
                                offset += 4 + Int(dataLen)
                            }
                        }
                    }
                }
            }
            
            // Fallback directory detection from long name
            if longName.hasPrefix("d") {
                isDir = true
            }
            
            // Skip "." and ".." in directory listings to prevent duplicate entries and invalid relative pathing
            if !parentPath.isEmpty && (fileName == "." || fileName == "..") {
                continue
            }
            
            let fullPath: String
            if fileName.hasPrefix("/") {
                fullPath = fileName
            } else if parentPath.isEmpty {
                fullPath = fileName
            } else if parentPath == "/" {
                fullPath = "/\(fileName)"
            } else if parentPath.hasSuffix("/") {
                fullPath = "\(parentPath)\(fileName)"
            } else {
                fullPath = "\(parentPath)/\(fileName)"
            }
            
            let isParent = (fileName == "..")
            let item = FileItem(
                name: fileName,
                path: fullPath,
                isDirectory: isDir || isParent,
                isParentDirectory: isParent,
                size: fileSize,
                modificationDate: modDate,
                permissions: longName,
                isRemote: true
            )
            items.append(item)
        }
        
        return items
    }
    
    // MARK: - Elevated Sudo Operations (Read / Write with Sudo)
    
    /// Reads a remote file using elevated privileges (`sudo cat`) via SSH command channel.
    public func executeSudoRead(
        remotePath: String,
        connection: SSHConnection,
        password: String? = nil
    ) async throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-o", "ConnectTimeout=15"
        ]
        if password == nil || password?.isEmpty == true {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
        }
        if connection.port != 22 {
            args.append(contentsOf: ["-p", "\(connection.port)"])
        }
        if let idFile = connection.identityFile, !idFile.isEmpty {
            let expanded = NSString(string: idFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        if let proxy = connection.proxyJump, !proxy.isEmpty {
            args.append(contentsOf: ["-J", proxy])
        }
        
        args.append(connection.destinationString)
        
        let escapedPath = remotePath.replacingOccurrences(of: "\"", with: "\\\"")
        let sudoFlag = (password != nil && !password!.isEmpty) ? "-S -p ''" : "-n"
        args.append("sudo \(sudoFlag) cat -- \"\(escapedPath)\"")
        
        proc.arguments = args
        let inP = Pipe()
        let outP = Pipe()
        let errP = Pipe()
        proc.standardInput = inP
        proc.standardOutput = outP
        proc.standardError = errP
        
        try proc.run()
        
        if let pw = password, !pw.isEmpty {
            if let pwData = "\(pw)\n".data(using: .utf8) {
                try? inP.fileHandleForWriting.write(contentsOf: pwData)
            }
        }
        try? inP.fileHandleForWriting.close()
        
        let outputData = outP.fileHandleForReading.readDataToEndOfFile()
        let errData = errP.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        
        if proc.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8) ?? "Error ejecutando sudo cat"
            let trimmed = errMsg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("password") || trimmed.lowercased().contains("a password is required") || trimmed.lowercased().contains("incorrect") {
                throw SFTPError.permissionDenied("Contraseña de sudo requerida o incorrecta.")
            }
            throw SFTPError.protocolError(trimmed.isEmpty ? "Error leyendo archivo con sudo (status \(proc.terminationStatus))" : trimmed)
        }
        
        return outputData
    }
    
    /// Writes content to a remote file using elevated privileges (`sudo tee`) via SSH command channel.
    public func executeSudoWrite(
        remotePath: String,
        data: Data,
        connection: SSHConnection,
        password: String? = nil
    ) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        
        var args = [
            "-o", "ConnectTimeout=15"
        ]
        if password == nil || password?.isEmpty == true {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
        }
        if connection.port != 22 {
            args.append(contentsOf: ["-p", "\(connection.port)"])
        }
        if let idFile = connection.identityFile, !idFile.isEmpty {
            let expanded = NSString(string: idFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        if let proxy = connection.proxyJump, !proxy.isEmpty {
            args.append(contentsOf: ["-J", proxy])
        }
        
        args.append(connection.destinationString)
        
        let escapedPath = remotePath.replacingOccurrences(of: "\"", with: "\\\"")
        let sudoFlag = (password != nil && !password!.isEmpty) ? "-S -p ''" : "-n"
        args.append("sudo \(sudoFlag) tee -- \"\(escapedPath)\" > /dev/null")
        
        proc.arguments = args
        let inP = Pipe()
        let outP = Pipe()
        let errP = Pipe()
        proc.standardInput = inP
        proc.standardOutput = outP
        proc.standardError = errP
        
        try proc.run()
        
        var fullPayload = Data()
        if let pw = password, !pw.isEmpty {
            if let pwData = "\(pw)\n".data(using: .utf8) {
                fullPayload.append(pwData)
            }
        }
        fullPayload.append(data)
        
        try? inP.fileHandleForWriting.write(contentsOf: fullPayload)
        try? inP.fileHandleForWriting.close()
        
        let errData = errP.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        
        if proc.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8) ?? "Error guardando con sudo"
            let trimmed = errMsg.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("password") || trimmed.lowercased().contains("a password is required") || trimmed.lowercased().contains("incorrect") {
                throw SFTPError.permissionDenied("Contraseña de sudo requerida o incorrecta.")
            }
            throw SFTPError.protocolError(trimmed.isEmpty ? "Error escribiendo archivo con sudo (status \(proc.terminationStatus))" : trimmed)
        }
    }
}

// MARK: - Binary Extensions
private extension UInt32 {
    var bigEndianBytes: Data {
        var val = self.bigEndian
        return Data(bytes: &val, count: MemoryLayout<UInt32>.size)
    }
}

private extension UInt64 {
    var bigEndianBytes: Data {
        var val = self.bigEndian
        return Data(bytes: &val, count: MemoryLayout<UInt64>.size)
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let idx = startIndex + offset
        return (UInt32(self[idx]) << 24)
             | (UInt32(self[idx + 1]) << 16)
             | (UInt32(self[idx + 2]) << 8)
             |  UInt32(self[idx + 3])
    }
    
    func readUInt64BE(at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= count else { return nil }
        let idx = startIndex + offset
        return (UInt64(self[idx]) << 56)
             | (UInt64(self[idx + 1]) << 48)
             | (UInt64(self[idx + 2]) << 40)
             | (UInt64(self[idx + 3]) << 32)
             | (UInt64(self[idx + 4]) << 24)
             | (UInt64(self[idx + 5]) << 16)
             | (UInt64(self[idx + 6]) << 8)
             |  UInt64(self[idx + 7])
    }
}
