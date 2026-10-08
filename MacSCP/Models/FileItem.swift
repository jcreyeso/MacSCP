import Foundation
import SwiftUI

/// Represents a local or remote filesystem item (file or folder).
public struct FileItem: Identifiable, Hashable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var isDirectory: Bool
    public var isParentDirectory: Bool
    public var size: Int64
    public var modificationDate: Date?
    public var permissions: String?
    public var isRemote: Bool
    
    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        isParentDirectory: Bool = false,
        size: Int64 = 0,
        modificationDate: Date? = nil,
        permissions: String? = nil,
        isRemote: Bool = false
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isParentDirectory = isParentDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.isRemote = isRemote
    }
    
    /// File extension without leading dot (e.g., "txt", "swift", "json").
    public var fileExtension: String {
        if isDirectory {
            return ""
        }
        let ext = (name as NSString).pathExtension
        return ext.lowercased()
    }
    
    /// File extension formatted for display.
    public var displayExtension: String {
        if isDirectory {
            return "Carpeta"
        }
        let ext = fileExtension
        return ext.isEmpty ? "—" : ext.uppercased()
    }
    
    /// User-friendly formatted file size string.
    public var formattedSize: String {
        if isDirectory {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Formatted date string.
    public var formattedDate: String {
        guard let date = modificationDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Icon name according to requirement:
    /// "Inicialmente solo colocar icono de folder e icono de archivo, mostrando extensión del archivo"
    public var systemIconName: String {
        if isParentDirectory {
            return "arrow.up.circle.fill"
        }
        if isDirectory {
            return "folder.fill"
        }
        return "doc.fill"
    }
    
    /// Icon tint color.
    public var iconColor: Color {
        if isParentDirectory {
            return .accentColor
        }
        if isDirectory {
            return .blue
        }
        return .secondary
    }
}

/// Columns available for sorting in file panels.
public enum SortColumn: String, Codable, CaseIterable {
    case name
    case size
    case date
}

/// Sort directions (ascending or descending).
public enum SortDirection: String, Codable, CaseIterable {
    case ascending
    case descending
    
    public mutating func toggle() {
        self = (self == .ascending) ? .descending : .ascending
    }
}

