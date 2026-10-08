import SwiftUI

/// Dialog for quick server-side copy to another remote path (Requirement 5).
public struct RemoteCopySheet: View {
    @ObservedObject public var viewModel: AppViewModel
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
                Text("Copiar en Servidor Remoto")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Text("Ejecuta la copia directamente en el servidor remoto de forma instantánea, sin transferir datos a través de tu Mac.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                // Source
                VStack(alignment: .leading, spacing: 4) {
                    Text("Origen:")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ruta de destino en el servidor:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    TextField("Ruta absoluta o relativa...", text: $viewModel.remoteCopyDestinationPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(.vertical, 4)
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancelar") {
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
                
                Button("Copiar en Servidor") {
                    viewModel.executeRemoteCopy()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPerformingRemoteCopy || viewModel.remoteCopyDestinationPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

