import Foundation
import SwiftUI
import Combine

// MARK: - Supported App Languages
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
    
    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        }
    }
}

// MARK: - Localization Keys
public enum L10nKey: String, CaseIterable {
    // Toolbar & General Navigation
    case appName
    case connectedTo
    case disconnect
    case sshConnections
    case selectSSHConnectionHelp
    case aboutMacSCP
    case githubRepo
    case settings
    case language
    case preferences
    case sudoRoot
    case upload
    case download
    case uploadHelp
    case downloadHelp
    case connected
    case notConnected
    
    // File Browser Panels
    case localPanel
    case remotePanel
    case name
    case size
    case modified
    case type
    case emptyFolder
    case noFilesInDirectory
    case createFolder
    case newFolder
    case createNewFolderIn
    case folderName
    case create
    case cancel
    case close
    case save
    case uploadToServer
    case downloadToMac
    case openEdit
    case openFile
    case openInNextpad
    case copyToAnotherLocation
    case copyPath
    case addToFavorites
    case delete
    case itemsCount
    case singleItem
    case selectedCount
    case errorCreatingFolder
    case invalidFolderNameError
    case folderCreatedSuccess
    case folderCreatedPermissionError
    
    // PathHeader
    case goUpOneLevel
    case currentPathPrefix
    case copyPathToClipboard
    case goToPath
    case reloadFileList
    case favorites
    case addCurrentToFavorites
    case noSavedFavorites
    case removeFromFavorites
    case invalidPath
    case go
    
    // Connections Sheet
    case searchConnectionsPlaceholder
    case reloadSSHConfig
    case newConnection
    case connect
    case connectWithSudo
    case connectionsFound
    case noConnectionsFound
    case noConnectionsMatchingSearch
    case editConnection
    case serverHost
    case port
    case user
    case privateKey
    case jumpHost
    case sudoSFTPElevation
    case useSudoHelp
    case manualConnection
    case aliasField
    
    // Remote Copy Sheet
    case copyOnServer
    case destinationPathOnServer
    case source
    case recentPaths
    case copy
    case clearRecent
    case selectOrEnterDestination
    case copyOnServerHelp
    case noRecentPaths
    
    // Transfer Progress
    case transferring
    case uploading
    case downloading
    case speed
    case remaining
    case bytes
    case completed
    
    // Toasts & Notifications
    case connectionEstablished
    case disconnectedSuccess
    case connectionError
    case fileSavedAndSynced
    case copyCompleted
    case pathCopiedSuccess
    
    // Settings Window
    case generalSettings
    case selectAppLanguage
    case defaultEditor
    case nextpadDefault
    case versionLabel
    case licenseLabel
    case openSourceGPLv3
    case settingsTitle
    case languageChangedNotice
}

// MARK: - Localization Service (ObservableObject)
public final class LocalizationService: ObservableObject {
    public static let shared = LocalizationService()
    
    private let userDefaultsKey = "MacSCP_SelectedLanguage"
    
    @Published public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: userDefaultsKey)
        }
    }
    
    private init() {
        if let savedLang = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: savedLang) {
            self.currentLanguage = lang
        } else {
            // Default to system locale if Spanish, otherwise English
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.starts(with: "es") {
                self.currentLanguage = .spanish
            } else {
                self.currentLanguage = .english
            }
        }
    }
    
    public func setLanguage(_ language: AppLanguage) {
        self.currentLanguage = language
    }
    
    public subscript(key: L10nKey) -> String {
        return t(key)
    }
    
    public func t(_ key: L10nKey) -> String {
        if let translation = Self.translations[currentLanguage]?[key] {
            return translation
        }
        // Fallback to English, then key name
        return Self.translations[.english]?[key] ?? key.rawValue
    }
    
    public func t(_ key: L10nKey, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, arguments: args)
    }
    
    // MARK: - Translation Dictionaries
    private static let translations: [AppLanguage: [L10nKey: String]] = [
        .spanish: [
            // Toolbar & General
            .appName: "MacSCP",
            .connectedTo: "Conectado a:",
            .disconnect: "Desconectar",
            .sshConnections: "Conexiones SSH",
            .selectSSHConnectionHelp: "Seleccionar conexión SSH desde ~/.ssh/config",
            .aboutMacSCP: "Acerca de MacSCP",
            .githubRepo: "Ver repositorio en GitHub (jcreyeso/MacSCP)",
            .settings: "Configuración",
            .language: "Idioma",
            .preferences: "Preferencias",
            .sudoRoot: "SUDO ROOT",
            .upload: "Subir",
            .download: "Bajar",
            .uploadHelp: "Subir archivo local seleccionado al servidor remoto",
            .downloadHelp: "Descargar archivo remoto seleccionado a la Mac",
            .connected: "Conectado",
            .notConnected: "Desconectado",
            
            // File Browser
            .localPanel: "Local",
            .remotePanel: "Remoto",
            .name: "Nombre",
            .size: "Tamaño",
            .modified: "Modificado",
            .type: "Tipo",
            .emptyFolder: "Carpeta vacía",
            .noFilesInDirectory: "No hay archivos en este directorio",
            .createFolder: "Crear Carpeta",
            .newFolder: "Nueva Carpeta",
            .createNewFolderIn: "Crear nueva carpeta en:",
            .folderName: "Nombre de la carpeta:",
            .create: "Crear",
            .cancel: "Cancelar",
            .close: "Cerrar",
            .save: "Guardar",
            .uploadToServer: "Subir a servidor",
            .downloadToMac: "Bajar a Mac",
            .openEdit: "Abrir / Editar",
            .openFile: "Abrir archivo",
            .openInNextpad: "Abrir en Nextpad++",
            .copyToAnotherLocation: "Copiar a otra ubicación en servidor...",
            .copyPath: "Copiar ruta",
            .addToFavorites: "Añadir a favoritos",
            .delete: "Eliminar",
            .itemsCount: "%d elementos",
            .singleItem: "1 elemento",
            .selectedCount: "%d seleccionados",
            .errorCreatingFolder: "Error al crear carpeta",
            .invalidFolderNameError: "El nombre no puede estar vacío ni contener '/' o ':'.",
            .folderCreatedSuccess: "Carpeta creada exitosamente",
            .folderCreatedPermissionError: "Error al crear carpeta: permiso denegado. Prueba conectando con Sudo SFTP.",
            
            // PathHeader
            .goUpOneLevel: "Subir un nivel (..)",
            .currentPathPrefix: "Ruta actual: ",
            .copyPathToClipboard: "Copiar ruta al portapapeles",
            .goToPath: "Ir a ruta...",
            .reloadFileList: "Recargar lista de archivos",
            .favorites: "Favoritos",
            .addCurrentToFavorites: "Añadir ruta actual a favoritos",
            .noSavedFavorites: "No hay favoritos guardados",
            .removeFromFavorites: "Eliminar de favoritos",
            .invalidPath: "Ruta inválida",
            .go: "Ir",
            
            // Connections Sheet
            .searchConnectionsPlaceholder: "Buscar por alias, host o usuario...",
            .reloadSSHConfig: "Recargar ~/.ssh/config",
            .newConnection: "Nueva Conexión",
            .connect: "Conectar",
            .connectWithSudo: "Conectar con Sudo",
            .connectionsFound: "Conexiones encontradas (%d)",
            .noConnectionsFound: "No se encontraron conexiones",
            .noConnectionsMatchingSearch: "No hay conexiones que coincidan con la búsqueda.",
            .editConnection: "Editar conexión",
            .serverHost: "Servidor / Host",
            .port: "Puerto",
            .user: "Usuario",
            .privateKey: "Clave Privada (IdentityFile)",
            .jumpHost: "Salto (ProxyJump)",
            .sudoSFTPElevation: "Elevación Sudo SFTP",
            .useSudoHelp: "Usar sudo para acceso root completo",
            .manualConnection: "Conexión manual",
            .aliasField: "Alias",
            
            // Remote Copy Sheet
            .copyOnServer: "Copiar en Servidor",
            .destinationPathOnServer: "Ruta de destino en el servidor:",
            .source: "Origen:",
            .recentPaths: "Rutas Recientes",
            .copy: "Copiar",
            .clearRecent: "Limpiar recientes",
            .selectOrEnterDestination: "Selecciona o ingresa una ruta de destino:",
            .copyOnServerHelp: "Copia directa en el servidor sin descargar a tu Mac",
            .noRecentPaths: "No hay rutas recientes",
            
            // Transfer Progress
            .transferring: "Transfiriendo...",
            .uploading: "Subiendo...",
            .downloading: "Descargando...",
            .speed: "Velocidad:",
            .remaining: "Restante:",
            .bytes: "Bytes:",
            .completed: "Completado",
            
            // Toasts & Notifications
            .connectionEstablished: "Conexión establecida con éxito",
            .disconnectedSuccess: "Desconectado",
            .connectionError: "Error al conectar",
            .fileSavedAndSynced: "Archivo guardado y sincronizado",
            .copyCompleted: "Copia completada con éxito",
            .pathCopiedSuccess: "Ruta copiada al portapapeles",
            
            // Settings Window
            .generalSettings: "General",
            .selectAppLanguage: "Idioma de la aplicación:",
            .defaultEditor: "Editor externo:",
            .nextpadDefault: "Nextpad++ (predeterminado si está instalado)",
            .versionLabel: "Versión:",
            .licenseLabel: "Licencia:",
            .openSourceGPLv3: "GNU General Public License v3.0 (GPLv3)",
            .settingsTitle: "Configuración de MacSCP",
            .languageChangedNotice: "El idioma se actualiza inmediatamente en toda la interfaz."
        ],
        
        .english: [
            // Toolbar & General
            .appName: "MacSCP",
            .connectedTo: "Connected to:",
            .disconnect: "Disconnect",
            .sshConnections: "SSH Connections",
            .selectSSHConnectionHelp: "Select SSH connection from ~/.ssh/config",
            .aboutMacSCP: "About MacSCP",
            .githubRepo: "View GitHub repository (jcreyeso/MacSCP)",
            .settings: "Settings",
            .language: "Language",
            .preferences: "Preferences",
            .sudoRoot: "SUDO ROOT",
            .upload: "Upload",
            .download: "Download",
            .uploadHelp: "Upload selected local file to remote server",
            .downloadHelp: "Download selected remote file to Mac",
            .connected: "Connected",
            .notConnected: "Disconnected",
            
            // File Browser
            .localPanel: "Local",
            .remotePanel: "Remote",
            .name: "Name",
            .size: "Size",
            .modified: "Modified",
            .type: "Type",
            .emptyFolder: "Empty folder",
            .noFilesInDirectory: "No files in this directory",
            .createFolder: "Create Folder",
            .newFolder: "New Folder",
            .createNewFolderIn: "Create new folder in:",
            .folderName: "Folder name:",
            .create: "Create",
            .cancel: "Cancel",
            .close: "Close",
            .save: "Save",
            .uploadToServer: "Upload to server",
            .downloadToMac: "Download to Mac",
            .openEdit: "Open / Edit",
            .openFile: "Open file",
            .openInNextpad: "Open in Nextpad++",
            .copyToAnotherLocation: "Copy to another location on server...",
            .copyPath: "Copy path",
            .addToFavorites: "Add to favorites",
            .delete: "Delete",
            .itemsCount: "%d items",
            .singleItem: "1 item",
            .selectedCount: "%d selected",
            .errorCreatingFolder: "Error creating folder",
            .invalidFolderNameError: "Folder name cannot be empty or contain '/' or ':'.",
            .folderCreatedSuccess: "Folder created successfully",
            .folderCreatedPermissionError: "Error creating folder: permission denied. Try connecting with Sudo SFTP.",
            
            // PathHeader
            .goUpOneLevel: "Go up one level (..)",
            .currentPathPrefix: "Current path: ",
            .copyPathToClipboard: "Copy path to clipboard",
            .goToPath: "Go to path...",
            .reloadFileList: "Reload file list",
            .favorites: "Favorites",
            .addCurrentToFavorites: "Add current path to favorites",
            .noSavedFavorites: "No saved favorites",
            .removeFromFavorites: "Remove from favorites",
            .invalidPath: "Invalid path",
            .go: "Go",
            
            // Connections Sheet
            .searchConnectionsPlaceholder: "Search by alias, host, or user...",
            .reloadSSHConfig: "Reload ~/.ssh/config",
            .newConnection: "New Connection",
            .connect: "Connect",
            .connectWithSudo: "Connect with Sudo",
            .connectionsFound: "Connections found (%d)",
            .noConnectionsFound: "No connections found",
            .noConnectionsMatchingSearch: "No connections match your search.",
            .editConnection: "Edit connection",
            .serverHost: "Server / Host",
            .port: "Port",
            .user: "User",
            .privateKey: "Private Key (IdentityFile)",
            .jumpHost: "Jump Host (ProxyJump)",
            .sudoSFTPElevation: "Sudo SFTP Elevation",
            .useSudoHelp: "Use sudo for full root access",
            .manualConnection: "Manual connection",
            .aliasField: "Alias",
            
            // Remote Copy Sheet
            .copyOnServer: "Copy on Server",
            .destinationPathOnServer: "Destination path on server:",
            .source: "Source:",
            .recentPaths: "Recent Paths",
            .copy: "Copy",
            .clearRecent: "Clear recent",
            .selectOrEnterDestination: "Select or enter a destination path:",
            .copyOnServerHelp: "Copy directly on server without downloading to Mac",
            .noRecentPaths: "No recent paths",
            
            // Transfer Progress
            .transferring: "Transferring...",
            .uploading: "Uploading...",
            .downloading: "Downloading...",
            .speed: "Speed:",
            .remaining: "Remaining:",
            .bytes: "Bytes:",
            .completed: "Completed",
            
            // Toasts & Notifications
            .connectionEstablished: "Connection established successfully",
            .disconnectedSuccess: "Disconnected",
            .connectionError: "Connection error",
            .fileSavedAndSynced: "File saved and synchronized",
            .copyCompleted: "Copy completed successfully",
            .pathCopiedSuccess: "Path copied to clipboard",
            
            // Settings Window
            .generalSettings: "General",
            .selectAppLanguage: "Application language:",
            .defaultEditor: "External editor:",
            .nextpadDefault: "Nextpad++ (default if installed)",
            .versionLabel: "Version:",
            .licenseLabel: "License:",
            .openSourceGPLv3: "GNU General Public License v3.0 (GPLv3)",
            .settingsTitle: "MacSCP Settings",
            .languageChangedNotice: "Language updates immediately throughout the application."
        ]
    ]
}
