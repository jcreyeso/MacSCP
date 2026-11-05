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
    public let onRename: ((FileItem, String) -> Void)?
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
    @State private var renamingItemPath: String? = nil
    @State private var inlineEditingName: String = ""
    @State private var typeSelectScrollTarget: String? = nil
    
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
        onRename: ((FileItem, String) -> Void)? = nil,
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
        self.onRename = onRename
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
                } : nil,
                onRename: onRename != nil ? {
                    if let path = selectedPath,
                       let item = items.first(where: { $0.path == path && !$0.isParentDirectory }) {
                        startRename(for: item)
                    }
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
                ScrollViewReader { proxy in
                    List(sortedItems, id: \.path, selection: $selectedPath) { item in
                        FileRowView(
                            item: item,
                            isRemote: isRemote,
                            isRenaming: renamingItemPath == item.path,
                            editingName: $inlineEditingName,
                            onCommitRename: { newName in
                                commitInlineRename(for: item, newName: newName)
                            },
                            onCancelRename: {
                                cancelInlineRename()
                            },
                            onDoubleClick: { onDoubleClick(item) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if renamingItemPath != item.path {
                                onDoubleClick(item)
                            }
                        }
                        .contextMenu {
                            buildContextMenu(for: item)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .onChange(of: typeSelectScrollTarget) { target in
                        guard let target else { return }
                        proxy.scrollTo(target)
                        typeSelectScrollTarget = nil
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .background(
            TypeSelectMonitor(
                isInitiallyActive: !isRemote,
                onType: handleTypeSelect,
                onOpen: handleOpenSelection
            )
        )
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
        .onChange(of: currentPath) { _ in
            cancelInlineRename()
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
    
    // MARK: - Type to Select
    /// Selects the first displayed item whose name starts with `typed`, like Finder.
    /// Returns false when the panel has no list to search, so the key press is left alone.
    private func handleTypeSelect(_ typed: String) -> Bool {
        guard !isLoading, !items.isEmpty else { return false }
        let match = sortedItems.first { item in
            !item.isParentDirectory && item.name.range(
                of: typed,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
        if let match {
            selectedPath = match.path
            typeSelectScrollTarget = match.path
        }
        return true
    }
    
    /// Opens the selected item, the same as double-clicking it.
    /// Returns false when nothing is selected, so the key press is left alone.
    private func handleOpenSelection() -> Bool {
        guard !isLoading, renamingItemPath == nil,
              let item = items.first(where: { $0.path == selectedPath }) else {
            return false
        }
        onDoubleClick(item)
        return true
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
                
                // Rename
                if onRename != nil {
                    Button(action: {
                        startRename(for: item)
                    }) {
                        Label(l10n[.rename], systemImage: "pencil")
                    }
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
                
                // Rename
                if onRename != nil {
                    Button(action: {
                        startRename(for: item)
                    }) {
                        Label(l10n[.rename], systemImage: "pencil")
                    }
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
    
    private func startRename(for item: FileItem) {
        guard !item.isParentDirectory else { return }
        selectedPath = item.path
        inlineEditingName = item.name
        renamingItemPath = item.path
    }
    
    private func commitInlineRename(for item: FileItem, newName: String) {
        guard renamingItemPath == item.path else { return }
        renamingItemPath = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        inlineEditingName = ""
        if !trimmed.isEmpty && trimmed != item.name {
            onRename?(item, trimmed)
        }
    }
    
    private func cancelInlineRename() {
        renamingItemPath = nil
        inlineEditingName = ""
    }
}

/// Sends typed characters to the panel it sits behind, while that panel is the active one.
private struct TypeSelectMonitor: NSViewRepresentable {
    let isInitiallyActive: Bool
    let onType: (String) -> Bool
    let onOpen: () -> Bool
    
    func makeNSView(context: Context) -> TypeSelectMonitorView {
        TypeSelectMonitorView()
    }
    
    func updateNSView(_ view: TypeSelectMonitorView, context: Context) {
        view.isInitiallyActive = isInitiallyActive
        view.onType = onType
        view.onOpen = onOpen
    }
}

private final class TypeSelectMonitorView: NSView {
    /// Pause after which the next key press starts a new search.
    private static let resetInterval: TimeInterval = 1.0
    private static weak var lastActivePanel: TypeSelectMonitorView?
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76
    
    var isInitiallyActive = false
    var onType: ((String) -> Bool)?
    var onOpen: (() -> Bool)?
    
    private var monitor: Any?
    private var typedText = ""
    private var lastKeyTimestamp: TimeInterval = 0
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }
    
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        
        if event.type != .keyDown {
            typedText = ""
            if frameInWindow.contains(event.locationInWindow) {
                Self.lastActivePanel = self
            }
            return event
        }
        
        guard isActivePanel(in: window),
              window.attachedSheet == nil,
              !(window.firstResponder is NSText) else {
            return event
        }
        
        // Opening a folder removes focus from the list, so remember which panel had it.
        Self.lastActivePanel = self
        
        // Command and Control combinations are shortcuts.
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else {
            typedText = ""
            return event
        }
        
        if event.keyCode == Self.returnKeyCode || event.keyCode == Self.keypadEnterKeyCode {
            typedText = ""
            // Holding the key down must not open the same file over and over.
            return event.isARepeat || onOpen?() == true ? nil : event
        }
        
        // Arrows and other control keys are not search text.
        guard let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy(Self.isTypeable) else {
            typedText = ""
            return event
        }
        
        let isNewSearch = event.timestamp - lastKeyTimestamp > Self.resetInterval
        let text = (isNewSearch ? "" : typedText) + characters
        
        // A leading space is not the start of a file name.
        guard !text.hasPrefix(" "), let onType, onType(text) else {
            typedText = ""
            return event
        }
        
        typedText = text
        lastKeyTimestamp = event.timestamp
        focusList(in: window)
        return nil
    }
    
    private var frameInWindow: NSRect {
        convert(bounds, to: nil)
    }
    
    private func isActivePanel(in window: NSWindow) -> Bool {
        // Keyboard focus decides first, so Tab can move between the panels.
        if let list = window.firstResponder as? NSTableView {
            let visible = list.convert(list.visibleRect, to: nil)
            return frameInWindow.contains(NSPoint(x: visible.midX, y: visible.midY))
        }
        if let active = Self.lastActivePanel, active.window === window {
            return active === self
        }
        return isInitiallyActive
    }
    
    /// Gives the list keyboard focus so the arrow keys continue from the match.
    private func focusList(in window: NSWindow) {
        guard !(window.firstResponder is NSTableView),
              let contentView = window.contentView else { return }
        let frame = frameInWindow
        let center = NSPoint(x: frame.midX, y: frame.midY)
        var view = contentView.hitTest(contentView.convert(center, from: nil))
        while let current = view, !(current is NSTableView) {
            view = current.superview
        }
        if let table = view {
            window.makeFirstResponder(table)
        }
    }
    
    private static func isTypeable(_ scalar: Unicode.Scalar) -> Bool {
        // Function keys and arrows arrive as private-use characters.
        !CharacterSet.controlCharacters.contains(scalar)
            && !CharacterSet(charactersIn: "\u{F700}"..."\u{F8FF}").contains(scalar)
    }
    
    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Row representing a file or folder item with folder/file icons and file extension (Requirement 6).
struct FileRowView: View {
    let item: FileItem
    let isRemote: Bool
    let isRenaming: Bool
    @Binding var editingName: String
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    let onDoubleClick: () -> Void
    
    @FocusState private var isRenameFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemIconName)
                .foregroundColor(item.iconColor)
                .font(.system(size: 14))
                .frame(width: 18)
            
            // File / Folder Name or Inline TextField
            if isRenaming {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
                    .frame(minWidth: 100, maxWidth: 320, alignment: .leading)
                    .focused($isRenameFocused)
                    .onSubmit {
                        onCommitRename(editingName)
                    }
                    .onExitCommand {
                        onCancelRename()
                    }
                    .onChange(of: isRenameFocused) { focused in
                        if !focused && isRenaming {
                            onCommitRename(editingName)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isRenameFocused = true
                        }
                    }
            } else {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundColor(item.isParentDirectory ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
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
