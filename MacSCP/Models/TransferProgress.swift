import Foundation

public enum TransferDirection: String, Codable {
    case upload = "Subiendo"
    case download = "Descargando"
    
    public var iconName: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        }
    }
}

/// Tracks real-time transfer progress, rate, and completion.
public struct TransferProgress: Identifiable {
    public var id = UUID()
    public var fileName: String
    public var direction: TransferDirection
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var currentSpeedBytesPerSec: Double
    public var isCompleted: Bool
    public var isPaused: Bool
    public var errorDescription: String?
    
    public init(
        fileName: String,
        direction: TransferDirection,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        currentSpeedBytesPerSec: Double = 0,
        isCompleted: Bool = false,
        isPaused: Bool = false,
        errorDescription: String? = nil
    ) {
        self.fileName = fileName
        self.direction = direction
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.currentSpeedBytesPerSec = currentSpeedBytesPerSec
        self.isCompleted = isCompleted
        self.isPaused = isPaused
        self.errorDescription = errorDescription
    }
    
    /// Progress fraction between 0.0 and 1.0.
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0.0 }
        let fraction = Double(bytesTransferred) / Double(totalBytes)
        return min(max(fraction, 0.0), 1.0)
    }
    
    /// Percentage formatted as a string (e.g., "75.4%").
    public var formattedPercentage: String {
        guard totalBytes > 0 else { return "0%" }
        let pct = fractionCompleted * 100.0
        return String(format: "%.1f%%", pct)
    }
    
    /// Transfer rate formatted string (e.g. "2.4 MB/s" or "Pausado").
    public var formattedSpeed: String {
        if isPaused { return "Pausado" }
        guard currentSpeedBytesPerSec > 0 else { return "0 KB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(currentSpeedBytesPerSec), countStyle: .file))/s"
    }
    
    /// Detailed summary e.g. "14.2 MB / 30.0 MB (47.3%) • 3.1 MB/s".
    public var detailedSummary: String {
        let transferredStr = ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let speedStr = isPaused ? "Pausado" : formattedSpeed
        return "\(transferredStr) / \(totalStr) (\(formattedPercentage)) • \(speedStr)"
    }
}

/// Thread-safe controller for pausing, resuming, and cancelling active transfers.
public final class TransferState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isPaused: Bool = false
    private var _isCancelled: Bool = false
    
    public init() {}
    
    public var isPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isPaused
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isPaused = newValue
        }
    }
    
    public var isCancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isCancelled = newValue
        }
    }
    
    public func pause() { isPaused = true }
    public func resume() { isPaused = false }
    public func cancel() { isCancelled = true }
    public func reset() {
        lock.lock()
        _isPaused = false
        _isCancelled = false
        lock.unlock()
    }
}

