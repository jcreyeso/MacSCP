import SwiftUI

/// Floating notification toast banner for feedback and sync notifications.
public struct ToastBannerView: View {
    public let toast: ToastItem
    public let onDismiss: () -> Void
    
    public init(toast: ToastItem, onDismiss: @escaping () -> Void) {
        self.toast = toast
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.type.iconName)
                .foregroundColor(toast.type.color)
                .font(.system(size: 14))
            
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .padding(.bottom, 12)
    }
}

