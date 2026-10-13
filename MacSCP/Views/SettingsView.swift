import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject private var l10n = LocalizationService.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Form Content
            Form {
                Section {
                    // Language Selection
                    Picker(selection: $l10n.currentLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            HStack {
                                Text(lang.flag)
                                Text(lang.displayName)
                            }
                            .tag(lang)
                        }
                    } label: {
                        Text(l10n[.selectAppLanguage])
                            .fontWeight(.medium)
                    }
                    .pickerStyle(.menu)
                    
                    Text(l10n[.languageChangedNotice])
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text(l10n[.language])
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                Section {
                    // External Editor
                    LabeledContent(l10n[.defaultEditor]) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.accentColor)
                            Text(l10n[.nextpadDefault])
                                .font(.callout)
                        }
                    }
                } header: {
                    Text(l10n[.generalSettings])
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .formStyle(.grouped)
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button(l10n[.close]) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 540, idealWidth: 560, maxWidth: 600, minHeight: 320, idealHeight: 340)
    }
}
