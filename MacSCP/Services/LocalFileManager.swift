import Foundation

/// Service for local file system navigation and operations.
public final class LocalFileManager {
    public static let shared = LocalFileManager()
    
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// User's home directory path.
    public var homePath: String {
        return fileManager.homeDirectoryForCurrentUser.path
    }
    
    /// Lists contents of a local directory, sorted with folders first.
    public func listDirectory(at path: String) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var items: [FileItem] = []
        
        // Add ".." parent directory entry if not at root
        if path != "/" {
            let parentPath = (path as NSString).deletingLastPathComponent
            items.append(FileItem(
                name: "..",
                path: parentPath.isEmpty ? "/" : parentPath,
                isDirectory: true,
                isParentDirectory: true,
                size: 0,
                modificationDate: nil,
                isRemote: false
            ))
        }
        
        for fileURL in contents {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = Int64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate
            
            let item = FileItem(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDir,
                isParentDirectory: false,
                size: size,
                modificationDate: modDate,
                permissions: nil,
                isRemote: false
            )
            items.append(item)
        }
        
        return items.sorted { a, b in
            if a.isParentDirectory { return true }
            if b.isParentDirectory { return false }
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    
    /// Returns the parent directory path.
    public func parentPath(of currentPath: String) -> String {
        guard currentPath != "/" else { return "/" }
        let parent = (currentPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
    
    /// Creates a new folder at the given path.
    public func createFolder(named name: String, in parentPath: String) throws {
        let target = (parentPath as NSString).appendingPathComponent(name)
        try fileManager.createDirectory(atPath: target, withIntermediateDirectories: false)
    }
    
    /// Deletes the item at the given path.
    public func deleteItem(at path: String) throws {
        try fileManager.removeItem(atPath: path)
    }
}

