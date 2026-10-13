import SwiftUI
import AppKit

/// Navigation panel showing file list with icons, extension, size, and date (Requirement 6).
public struct FileBrowserPanel: View {
    public let isRemote: Bool
    public let title: String
    @Binding public var currentPath: String
    public let items: [FileItem]
    public let isLoading: Bool
    @Binding public var selectedPath: String?
    public let isConnected: Bool
    public let favorites: [String]
    @Binding public var sortColumn: SortColumn
    @Binding public var sortDirection: SortDirection
    public let onSortChanged: ((SortColumn, SortDirection) -> Void)?
    
    public let onDoubleClick: (FileItem) -> Void
    public let onNavigate: (String) -> Void
    public let onNavigateUp: () -> Void
    public let onRefresh: () -> Void
    public let onGoHome: (() -> Void)?
    public let onToggleFavorite: ((String) -> Void)?
    public let onRemoveFavorite: ((String) -> Void)?
    
    // Actions
    public let onCreateFolder: ((String) -> Void)?
    public let onUpload: ((FileItem) -> Void)?
    public let onDownload: ((FileItem) -> Void)?
    public let onEditInNextpad: ((FileItem) -> Void)?
    public let onEditInNextpadWithSudo: ((FileItem) -> Void)?
    public let onRemoteCopy: ((FileItem) -> Void)?
    public let onDelete: ((FileItem) -> Void)?
    public let onCopyPath: (String) -> Void
    
    @ObservedObject private var l10n = LocalizationService.shared
    @State private var isShowingNewFolderDialog: Bool = false
    @State private var newFolderName: String = ""
    
    public init(
        isRemote: Bool,
        title: String,
        currentPath: Binding<String>,
        items: [FileItem],
        isLoading: Bool,
        selectedPath: Binding<String?>,
        isConnected: Bool = true,
        favorites: [String] = [],
        sortColumn: Binding<SortColumn> = .constant(.name),
        sortDirection: Binding<SortDirection> = .constant(.ascending),
        onSortChanged: ((SortColumn, SortDirection) -> Void)? = nil,
        onDoubleClick: @escaping (FileItem) -> Void,
        onNavigate: @escaping (String) -> Void,
        onNavigateUp: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onGoHome: (() -> Void)? = nil,
        onToggleFavorite: ((String) -> Void)? = nil,
        onRemoveFavorite: ((String) -> Void)? = nil,
        onCreateFolder: ((String) -> Void)? = nil,
        onUpload: ((FileItem) -> Void)? = nil,
        onDownload: ((FileItem) -> Void)? = nil,
        onEditInNextpad: ((FileItem) -> Void)? = nil,
        onEditInNextpadWithSudo: ((FileItem) -> Void)? = nil,
        onRemoteCopy: ((FileItem) -> Void)? = nil,
        onDelete: ((FileItem) -> Void)? = nil,
        onCopyPath: @escaping (String) -> Void
    ) {
        self.isRemote = isRemote
        self.title = title
        self._currentPath = currentPath
        self.items = items
        self.isLoading = isLoading
        self._selectedPath = selectedPath
        self.isConnected = isConnected
        self.favorites = favorites
        self._sortColumn = sortColumn
        self._sortDirection = sortDirection
        self.onSortChanged = onSortChanged
        self.onDoubleClick = onDoubleClick
        self.onNavigate = onNavigate
        self.onNavigateUp = onNavigateUp
        self.onRefresh = onRefresh
        self.onGoHome = onGoHome
        self.onToggleFavorite = onToggleFavorite
        self.onRemoveFavorite = onRemoveFavorite
        self.onCreateFolder = onCreateFolder
        self.onUpload = onUpload
        self.onDownload = onDownload
        self.onEditInNextpad = onEditInNextpad
        self.onEditInNextpadWithSudo = onEditInNextpadWithSudo
        self.onRemoteCopy = onRemoteCopy
        self.onDelete = onDelete
        self.onCopyPath = onCopyPath
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Path Header (Requirement 7)
            PathHeaderView(
                title: title,
                currentPath: $currentPath,
                showPathInput: !isRemote || isConnected,
                favorites: favorites,
                onNavigate: onNavigate,
                onNavigateUp: onNavigateUp,
                onRefresh: onRefresh,
                onGoHome: onGoHome,
                onToggleFavorite: onToggleFavorite,
                onRemoveFavorite: onRemoveFavorite,
                onCreateFolder: onCreateFolder != nil ? {
                    newFolderName = ""
                    isShowingNewFolderDialog = true
                } : nil
            )
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Column Header Bar (Sort Asc/Desc by Name, Size, Date)
            columnHeaderBar
            
            Divider()
            
            // File List Table
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView(l10n.currentLanguage == .spanish ? "Cargando archivos..." : "Loading files...")
                        .progressViewStyle(.circular)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(isRemote && (!isConnected || currentPath.isEmpty) ? l10n[.notConnected] : l10n[.emptyFolder])
                        .foregroundColor(.secondary)
                        .font(.callout)
                    if onCreateFolder != nil && (!isRemote || isConnected) {
                        Button(action: {
                            newFolderName = ""
                            isShowingNewFolderDialog = true
                        }) {
                            Label(l10n[.newFolder], systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedItems, id: \.path, selection: $selectedPath) { item in
                    FileRowView(
                        item: item,
                        isRemote: isRemote,
                        onDoubleClick: { onDoubleClick(item) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onDoubleClick(item)
                    }
                    .contextMenu {
                        buildContextMenu(for: item)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert(l10n[.newFolder], isPresented: $isShowingNewFolderDialog) {
            TextField(l10n[.folderName], text: $newFolderName)
            Button(l10n[.create]) {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCreateFolder?(trimmed)
                }
                newFolderName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button(l10n[.cancel], role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text(isRemote 
                 ? (l10n.currentLanguage == .spanish ? "Ingresa el nombre para la nueva carpeta en el servidor:" : "Enter name for the new folder on the server:")
                 : (l10n.currentLanguage == .spanish ? "Ingresa el nombre para la nueva carpeta en tu Mac:" : "Enter name for the new folder on your Mac:"))
        }
    }
    
    // MARK: - Sorted Items
    private var sortedItems: [FileItem] {
        let parentItems = items.filter { $0.isParentDirectory }
        let regularItems = items.filter { !$0.isParentDirectory }
        
        let sorted = regularItems.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            
            switch sortColumn {
            case .name:
                let comp = a.name.localizedStandardCompare(b.name)
                return sortDirection == .ascending ? (comp == .orderedAscending) : (comp == .orderedDescending)
                
            case .size:
                if a.size != b.size {
                    return sortDirection == .ascending ? (a.size < b.size) : (a.size > b.size)
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
                
            case .date:
                let dateA = a.modificationDate ?? Date.distantPast
                let dateB = b.modificationDate ?? Date.distantPast
                if dateA != dateB {
                    return sortDirection == .ascending ? (dateA < dateB) : (dateA > dateB)
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        
        return parentItems + sorted
    }
    
    // MARK: - Column Header Bar
    private var columnHeaderBar: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 18, height: 1)
            
            columnHeaderButton(title: l10n[.name], column: .name, alignment: .leading)
            
            columnHeaderButton(title: l10n[.size], column: .size, width: 75, alignment: .trailing)
            
            columnHeaderButton(title: l10n[.modified], column: .date, width: 105, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func columnHeaderButton(title: String, column: SortColumn, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                setSort(to: column)
            }
        }) {
            HStack(spacing: 4) {
                if alignment == .trailing {
                    Spacer()
                }
                
                Text(title)
                    .font(.system(size: 11, weight: sortColumn == column ? .bold : .medium))
                    .foregroundColor(sortColumn == column ? .primary : .secondary)
                
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                
                if alignment == .leading {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .help("\(title) (\(sortColumn == column ? (sortDirection == .ascending ? "↑" : "↓") : ""))")
    }
    
    private func setSort(to column: SortColumn) {
        if sortColumn == column {
            sortDirection.toggle()
        } else {
            sortColumn = column
            sortDirection = (column == .date) ? .descending : .ascending
        }
        onSortChanged?(sortColumn, sortDirection)
    }
    
    @ViewBuilder
    private func buildContextMenu(for item: FileItem) -> some View {
        if item.isParentDirectory {
            Button(action: { onNavigateUp() }) {
                Label(l10n[.goUpOneLevel], systemImage: "arrow.up")
            }
            if onCreateFolder != nil {
                Divider()
                Button(action: {
                    newFolderName = ""
                    isShowingNewFolderDialog = true
                }) {
                    Label("\(l10n[.newFolder])...", systemImage: "folder.badge.plus")
                }
            }
        } else {
            if isRemote {
                // Remote Context Menu
                if onCreateFolder != nil {
                    Button(action: {
                        newFolderName = ""
                        isShowingNewFolderDialog = true
                    }) {
                        Label("\(l10n[.newFolder])...", systemImage: "folder.badge.plus")
                    }
                    Divider()
                }
                
                if !item.isDirectory {
                    Button(action: { onEditInNextpad?(item) }) {
                        Label(l10n.currentLanguage == .spanish ? "Editar en Nextpad++" : "Edit in Nextpad++", systemImage: "pencil.circle")
                    }
                } else {
                    Button(action: { onDoubleClick(item) }) {
                        Label(l10n.currentLanguage == .spanish ? "Abrir carpeta" : "Open folder", systemImage: "folder")
                    }
                }
                
                // Download to Mac
                Button(action: { onDownload?(item) }) {
                    Label(
                        item.isDirectory 
                            ? (l10n.currentLanguage == .spanish ? "Descargar carpeta a local" : "Download folder to Mac")
                            : l10n[.downloadToMac],
                        systemImage: "arrow.down.circle"
                    )
                }
                
                // Server-side copy
                Button(action: { onRemoteCopy?(item) }) {
                    Label(l10n[.copyToAnotherLocation], systemImage: "doc.on.doc")
                }
                
                Divider()
                
                // Delete
                if let onDelete = onDelete {
                    Button(role: .destructive, action: { onDelete(item) }) {
                        Label(
                            item.isDirectory 
                                ? (l10n.currentLanguage == .spanish ? "Eliminar carpeta del servidor" : "Delete folder from server")
                                : (l10n.currentLanguage == .spanish ? "Eliminar archivo del servidor" : "Delete file from server"),
                            systemImage: "trash"
                        )
                    }
                }
            } else {
                // Local Context Menu
                if onCreateFolder != nil {
                    Button(action: {
                        newFolderName = ""
                        isShowingNewFolderDialog = true
                    }) {
                        Label("\(l10n[.newFolder])...", systemImage: "folder.badge.plus")
                    }
                    Divider()
                }
                
                if item.isDirectory {
                    Button(action: { onDoubleClick(item) }) {
                        Label(l10n.currentLanguage == .spanish ? "Abrir carpeta" : "Open folder", systemImage: "folder")
                    }
                }
                
                // Upload to server
                if isConnected {
                    Button(action: { onUpload?(item) }) {
                        Label(
                            item.isDirectory 
                                ? (l10n.currentLanguage == .spanish ? "Subir carpeta a servidor" : "Upload folder to server")
                                : l10n[.uploadToServer],
                            systemImage: "arrow.up.circle"
                        )
                    }
                }
                
                Button(action: {
                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                }) {
                    Label(l10n.currentLanguage == .spanish ? "Mostrar en Finder" : "Show in Finder", systemImage: "macwindow")
                }
                
                Divider()
                
                // Delete
                if let onDelete = onDelete {
                    Button(role: .destructive, action: { onDelete(item) }) {
                        Label(
                            item.isDirectory 
                                ? (l10n.currentLanguage == .spanish ? "Eliminar carpeta" : "Delete folder")
                                : (l10n.currentLanguage == .spanish ? "Eliminar archivo" : "Delete file"),
                            systemImage: "trash"
                        )
                    }
                }
            }
            
            Divider()
            
            Button(action: { onCopyPath(item.path) }) {
                Label(l10n[.copyPath], systemImage: "doc.on.clipboard")
            }
        }
    }
}

/// Row representing a file or folder item with folder/file icons and file extension (Requirement 6).
struct FileRowView: View {
    let item: FileItem
    let isRemote: Bool
    let onDoubleClick: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemIconName)
                .foregroundColor(item.iconColor)
                .font(.system(size: 14))
                .frame(width: 18)
            
            // File / Folder Name
            Text(item.name)
                .font(.system(size: 13))
                .foregroundColor(item.isParentDirectory ? .accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Extension (Requirement 6)
            if !item.isParentDirectory && !item.isDirectory && !item.fileExtension.isEmpty {
                Text(item.fileExtension.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
                    .foregroundColor(.secondary)
            }
            
            // Size
            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .trailing)
            
            // Date
            Text(item.formattedDate)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 105, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
