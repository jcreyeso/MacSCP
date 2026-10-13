import SwiftUI

/// Graphical SSH connection manager loading profiles by default from ~/.ssh/config (Requirement 1).
public struct ConnectionsSheet: View {
    @ObservedObject public var viewModel: AppViewModel
    @ObservedObject private var l10n = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingManualSheet = false
    @State private var manualAlias = ""
    @State private var manualHost = ""
    @State private var manualUser = ""
    @State private var manualPort = "22"
    @State private var manualIdentityFile = ""
    @State private var manualUseSudo = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n[.sshConnections])
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(l10n.currentLanguage == .spanish ? "Configuraciones detectadas en ~/.ssh/config" : "Configurations detected in ~/.ssh/config")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.loadSavedConnections()
                }) {
                    Label(l10n.currentLanguage == .spanish ? "Recargar" : "Reload", systemImage: "arrow.clockwise")
                }
                .help(l10n[.reloadSSHConfig])
                
                Button(action: {
                    showingManualSheet.toggle()
                }) {
                    Label(l10n[.newConnection], systemImage: "plus")
                }
            }
            .padding()
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(l10n.currentLanguage == .spanish ? "Filtrar servidores por alias, usuario o IP..." : "Filter servers by alias, user, or IP...", text: $viewModel.connectionSearchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.connectionSearchText.isEmpty {
                    Button(action: { viewModel.connectionSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Connections List
            if viewModel.filteredConnections.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(l10n[.noConnectionsFound])
                        .font(.headline)
                    Text(l10n.currentLanguage == .spanish ? "Puedes agregar servidores a ~/.ssh/config o usar el botón '+ Nueva Conexión'." : "You can add servers to ~/.ssh/config or use the '+ New Connection' button.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredConnections) { connection in
                    ConnectionRowView(
                        connection: connection,
                        isCurrent: viewModel.currentConnection?.id == connection.id,
                        isConnecting: viewModel.isConnecting,
                        onConnect: {
                            viewModel.connect(to: connection)
                        },
                        onConnectWithSudo: {
                            viewModel.connectWithSudo(to: connection)
                        }
                    )
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text(l10n.t(.connectionsFound, viewModel.filteredConnections.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(l10n[.close]) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 580, minHeight: 460)
        .sheet(isPresented: $showingManualSheet) {
            manualConnectionSheet
        }
    }
    
    // Manual Connection Sheet
    private var manualConnectionSheet: some View {
        VStack(spacing: 16) {
            Text(l10n.currentLanguage == .spanish ? "Agregar Conexión Manual" : "Add Manual Connection")
                .font(.headline)
            
            Form {
                TextField(l10n.currentLanguage == .spanish ? "Alias / Nombre:" : "Alias / Name:", text: $manualAlias, prompt: Text(l10n.currentLanguage == .spanish ? "ej. mi-servidor" : "e.g. my-server"))
                TextField(l10n[.serverHost] + ":", text: $manualHost, prompt: Text("ej. 192.168.1.100 o mydomain.com"))
                TextField(l10n[.user] + ":", text: $manualUser, prompt: Text("ej. root, ubuntu"))
                TextField(l10n[.port] + ":", text: $manualPort, prompt: Text("22"))
                TextField(l10n.currentLanguage == .spanish ? "Archivo de Clave (opcional):" : "Key File (optional):", text: $manualIdentityFile, prompt: Text("~/.ssh/id_rsa"))
                
                Toggle(l10n.currentLanguage == .spanish ? "Iniciar sesión SFTP con privilegios sudo (root)" : "Start SFTP session with sudo (root) privileges", isOn: $manualUseSudo)
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
            }
            .padding()
            
            HStack {
                Button(l10n[.cancel]) {
                    showingManualSheet = false
                }
                Spacer()
                Button(l10n.currentLanguage == .spanish ? "Guardar y Conectar" : "Save and Connect") {
                    let portInt = Int(manualPort) ?? 22
                    let newConn = SSHConnection(
                        alias: manualAlias.isEmpty ? manualHost : manualAlias,
                        hostName: manualHost,
                        user: manualUser,
                        port: portInt,
                        identityFile: manualIdentityFile.isEmpty ? nil : manualIdentityFile,
                        isManual: true,
                        useSudoSFTP: manualUseSudo
                    )
                    viewModel.connections.append(newConn)
                    showingManualSheet = false
                    viewModel.connect(to: newConn)
                }
                .disabled(manualHost.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 440, height: 310)
    }
}

/// Row displaying an SSH Host profile
struct ConnectionRowView: View {
    let connection: SSHConnection
    let isCurrent: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onConnectWithSudo: () -> Void
    @ObservedObject private var l10n = LocalizationService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.useSudoSFTP ? "shield.checkered" : "terminal.fill")
                .font(.system(size: 20))
                .foregroundColor(isCurrent ? (connection.useSudoSFTP ? .orange : .green) : .accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(connection.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                    
                    if isCurrent {
                        Text(connection.useSudoSFTP 
                             ? (l10n.currentLanguage == .spanish ? "CONECTADO (SUDO)" : "CONNECTED (SUDO)")
                             : (l10n.currentLanguage == .spanish ? "CONECTADO" : "CONNECTED"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(connection.useSudoSFTP ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundColor(connection.useSudoSFTP ? .orange : .green)
                            .cornerRadius(4)
                    } else if connection.useSudoSFTP {
                        Text("SUDO")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(connection.displaySubtitle)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    if let idFile = connection.identityFile, !idFile.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                            Text((idFile as NSString).lastPathComponent)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    if let jump = connection.proxyJump, !jump.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("via \(jump)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: onConnect) {
                    Label(l10n.currentLanguage == .spanish ? "Conectar normal (SFTP)" : "Connect normal (SFTP)", systemImage: "person.fill")
                }
                Button(action: onConnectWithSudo) {
                    Label(l10n.currentLanguage == .spanish ? "Conectar con Sudo (SFTP root)" : "Connect with Sudo (SFTP root)", systemImage: "lock.shield.fill")
                }
            } label: {
                if isCurrent {
                    Text(l10n.currentLanguage == .spanish ? "Reconectar" : "Reconnect")
                } else {
                    Text(l10n[.connect])
                }
            } primaryAction: {
                onConnect()
            }
            .menuStyle(.borderedButton)
            .disabled(isConnecting)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onConnect()
        }
    }
}
