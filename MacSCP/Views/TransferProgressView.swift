import SwiftUI

/// Transfer status bar showing real-time transfer rate, bytes, percentage, and pause/cancel controls.
public struct TransferProgressView: View {
    public let progress: TransferProgress
    public let onPause: (() -> Void)?
    public let onResume: (() -> Void)?
    public let onCancel: (() -> Void)?
    
    public init(
        progress: TransferProgress,
        onPause: (() -> Void)? = nil,
        onResume: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.progress = progress
        self.onPause = onPause
        self.onResume = onResume
        self.onCancel = onCancel
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Direction or paused icon
            Image(systemName: progress.isPaused ? "pause.circle.fill" : progress.direction.iconName)
                .font(.system(size: 16))
                .foregroundColor(progress.isPaused ? .orange : (progress.direction == .upload ? .blue : .green))
            
            // File Name & Direction
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(progress.isPaused ? "Pausado" : progress.direction.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(progress.isPaused ? .orange : .secondary)
                    
                    Text(progress.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                
                // Detailed bytes summary
                Text(progress.detailedSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 220, alignment: .leading)
            
            // Progress bar
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
                .tint(progress.isPaused ? .orange : .accentColor)
                .frame(maxWidth: .infinity)
            
            // Percentage Badge
            Text(progress.formattedPercentage)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 50, alignment: .trailing)
            
            // Speed Badge
            Text(progress.formattedSpeed)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(progress.isPaused ? .orange : .secondary)
                .frame(width: 80, alignment: .trailing)
            
            // Transfer controls (Pause/Resume & Cancel)
            HStack(spacing: 8) {
                // Pause / Resume Button
                Button(action: {
                    if progress.isPaused {
                        onResume?()
                    } else {
                        onPause?()
                    }
                }) {
                    Image(systemName: progress.isPaused ? "play.circle.fill" : "pause.circle")
                        .font(.system(size: 16))
                        .foregroundColor(progress.isPaused ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(progress.isPaused ? "Reanudar transferencia" : "Pausar transferencia")
                
                // Cancel Button
                Button(action: {
                    onCancel?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Cancelar y abortar transferencia")
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

