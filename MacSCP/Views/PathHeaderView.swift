import SwiftUI
import AppKit

/// Top navigation header displaying full path with editable address bar and right-click options (Requirement 7).
public struct PathHeaderView: View {
    public let title: String
    @Binding public var currentPath: String
    public let showPathInput: Bool
    public let favorites: [String]
    public let onNavigate: (String) -> Void
    public let onNavigateUp: () -> Void
    public let onRefresh: () -> Void
    public let onGoHome: (() -> Void)?
    public let onToggleFavorite: ((String) -> Void)?
    public let onRemoveFavorite: ((String) -> Void)?
    
    @State private var inputPath: String = ""
    @FocusState private var isFieldFocused: Bool
    
    public init(
        title: String,
        currentPath: Binding<String>,
        showPathInput: Bool = true,
        favorites: [String] = [],
        onNavigate: @escaping (String) -> Void,
        onNavigateUp: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onGoHome: (() -> Void)? = nil,
        onToggleFavorite: ((String) -> Void)? = nil,
        onRemoveFavorite: ((String) -> Void)? = nil
    ) {
        self.title = title
        self._currentPath = currentPath
        self.showPathInput = showPathInput
        self.favorites = favorites
        self.onNavigate = onNavigate
        self.onNavigateUp = onNavigateUp
        self.onRefresh = onRefresh
        self.onGoHome = onGoHome
        self.onToggleFavorite = onToggleFavorite
        self.onRemoveFavorite = onRemoveFavorite
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Go Home button (if available)
                if let onGoHome = onGoHome {
                    Button(action: onGoHome) {
                        Image(systemName: "house")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Ir a la carpeta inicial")
                }
                
                // Navigate Up (..)
                Button(action: onNavigateUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderless)
                .disabled(!showPathInput)
                .help("Subir un nivel (..)")
                
                // Refresh
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!showPathInput)
                .help("Actualizar lista de archivos")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            // Editable address bar with status indicators & actions
            if showPathInput {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundColor(isFieldFocused ? .accentColor : .secondary)
                        .font(.system(size: 11))
                    
                    TextField("Ingresar ruta (ej. /var/log, ~/Documentos)...", text: $inputPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($isFieldFocused)
                        .onSubmit {
                            submitPath()
                        }
                        .onExitCommand {
                            inputPath = currentPath
                            isFieldFocused = false
                        }
                    
                    if inputPath != currentPath {
                        // Revert button
                        Button(action: {
                            inputPath = currentPath
                            isFieldFocused = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Restablecer ruta actual (Esc)")
                        
                        // Go button
                        Button(action: submitPath) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help("Ir a la ruta (Enter)")
                    }
                    
                    // Star toggle button (Requirement: marcar como favorito)
                    if let onToggleFavorite = onToggleFavorite {
                        let isFav = favorites.contains(currentPath)
                        Button(action: {
                            onToggleFavorite(currentPath)
                        }) {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundColor(isFav ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isFav ? "Quitar de favoritos" : "Marcar ruta actual como favorita")
                    }
                    
                    // Favorites Menu (Requirement: lista de favoritos para navegar rápidamente)
                    favoritesMenu
                    
                    // Quick copy button
                    Button(action: copyPathToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Copiar ruta completa al portapapeles")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isFieldFocused ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isFieldFocused ? 1.0 : 0.5)
                )
                .contextMenu {
                    if let onToggleFavorite = onToggleFavorite {
                        let isFav = favorites.contains(currentPath)
                        Button(action: { onToggleFavorite(currentPath) }) {
                            Label(
                                isFav ? "Quitar de favoritos" : "Marcar ruta como favorita",
                                systemImage: isFav ? "star.slash" : "star"
                            )
                        }
                        Divider()
                    }
                    Button(action: copyPathToClipboard) {
                        Label("Copiar ruta al portapapeles", systemImage: "doc.on.doc")
                    }
                    Button(action: pasteFromClipboard) {
                        Label("Pegar ruta y navegar", systemImage: "doc.on.clipboard")
                    }
                    if inputPath != currentPath {
                        Button(action: {
                            inputPath = currentPath
                            isFieldFocused = false
                        }) {
                            Label("Restablecer ruta actual", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .onAppear {
            inputPath = currentPath
        }
        .onChange(of: currentPath) { newPath in
            inputPath = newPath
        }
    }
    
    // MARK: - Favorites Menu (Requirement: lista de favoritos para navegar rápidamente)
    private var favoritesMenu: some View {
        Menu {
            if let onToggleFavorite = onToggleFavorite {
                let isFav = favorites.contains(currentPath)
                Button(action: {
                    onToggleFavorite(currentPath)
                }) {
                    Label(
                        isFav ? "Quitar ruta actual de favoritos" : "Marcar ruta actual como favorita",
                        systemImage: isFav ? "star.slash" : "star"
                    )
                }
                
                Divider()
            }
            
            if favorites.isEmpty {
                Text("No hay rutas favoritas guardadas")
            } else {
                Section("Rutas Favoritas") {
                    ForEach(favorites, id: \.self) { favPath in
                        Button(action: {
                            inputPath = favPath
                            onNavigate(favPath)
                        }) {
                            HStack {
                                Text(favPath)
                                if favPath == currentPath {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                if let onRemoveFavorite = onRemoveFavorite {
                    Divider()
                    Menu("Eliminar de favoritos...") {
                        ForEach(favorites, id: \.self) { favPath in
                            Button(role: .destructive, action: {
                                onRemoveFavorite(favPath)
                            }) {
                                Label(favPath, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: favorites.contains(currentPath) ? "bookmark.fill" : "bookmark")
                .font(.system(size: 11))
                .foregroundColor(favorites.contains(currentPath) ? .yellow : .secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 14)
        .help("Rutas favoritas (Clic para ver lista y navegar rápidamente)")
    }
    
    private func submitPath() {
        let trimmed = inputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputPath = currentPath
            return
        }
        
        if trimmed == currentPath {
            onRefresh()
            isFieldFocused = false
            return
        }
        
        onNavigate(trimmed)
        isFieldFocused = false
    }
    
    private func copyPathToClipboard() {
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.setString(currentPath, forType: .string)
    }
    
    private func pasteFromClipboard() {
        let pboard = NSPasteboard.general
        if let string = pboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                inputPath = trimmed
                submitPath()
            }
        }
    }
}

