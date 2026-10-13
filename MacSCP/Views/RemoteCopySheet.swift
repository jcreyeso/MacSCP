import SwiftUI

/// Dialog for quick server-side copy to another remote path (Requirement 5).
public struct RemoteCopySheet: View {
    @ObservedObject public var viewModel: AppViewModel
    @ObservedObject private var l10n = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(l10n[.copyOnServer])
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Text(l10n[.copyOnServerHelp])
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 14) {
                // Source
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n[.source])
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.remoteCopySourceItem?.path ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
                
                // Destination input
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(l10n[.destinationPathOnServer])
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if !viewModel.remoteCopyRecentPaths.isEmpty {
                            Menu {
                                Section("\(l10n[.recentPaths]) (\(l10n.currentLanguage == .spanish ? "últimas 10" : "last 10"))") {
                                    ForEach(viewModel.remoteCopyRecentPaths, id: \.self) { path in
                                        Button(action: {
                                            viewModel.remoteCopyDestinationPath = path
                                        }) {
                                            Text(path)
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                Button(role: .destructive, action: {
                                    viewModel.clearRemoteCopyRecentPaths()
                                }) {
                                    Label(l10n.currentLanguage == .spanish ? "Borrar historial de rutas" : "Clear path history", systemImage: "trash")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    Text(l10n[.recentPaths])
                                }
                                .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help(l10n.currentLanguage == .spanish ? "Seleccionar una ruta reciente" : "Select a recent path")
                        }
                    }
                    
                    TextField(l10n.currentLanguage == .spanish ? "Ruta absoluta o relativa..." : "Absolute or relative path...", text: $viewModel.remoteCopyDestinationPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                
                // Recent paths list (last 10 paths)
                if !viewModel.remoteCopyRecentPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(l10n.currentLanguage == .spanish ? "Rutas usadas recientemente (máx. 10):" : "Recently used paths (max 10):")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(l10n.currentLanguage == .spanish ? "Haz clic para seleccionar" : "Click to select")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(viewModel.remoteCopyRecentPaths, id: \.self) { path in
                                    HStack(spacing: 6) {
                                        Button(action: {
                                            viewModel.remoteCopyDestinationPath = path
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "folder")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(viewModel.remoteCopyDestinationPath == path ? .accentColor : .secondary)
                                                
                                                Text(path)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                
                                                Spacer()
                                                
                                                if viewModel.remoteCopyDestinationPath == path {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: {
                                            viewModel.removeRemoteCopyRecentPath(path)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .help(l10n.currentLanguage == .spanish ? "Eliminar de la lista" : "Remove from list")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        viewModel.remoteCopyDestinationPath == path
                                            ? Color.accentColor.opacity(0.12)
                                            : Color(NSColor.controlBackgroundColor)
                                    )
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.vertical, 4)
            
            Divider()
            
            // Buttons
            HStack {
                Button(l10n[.cancel]) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isPerformingRemoteCopy)
                
                Spacer()
                
                if viewModel.isPerformingRemoteCopy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                }
                
                Button(l10n[.copyOnServer]) {
                    viewModel.executeRemoteCopy()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPerformingRemoteCopy || viewModel.remoteCopyDestinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}
