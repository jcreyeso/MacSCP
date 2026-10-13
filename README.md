# MacSCP

A native, lightweight, and modern macOS file transfer client inspired by WinSCP. Built entirely with SwiftUI and AppKit for speed, simplicity, and seamless integration with macOS.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Universal Binary](https://img.shields.io/badge/Arch-Universal%20(arm64%20%7C%20x86__64)-purple.svg)](https://github.com/jcreyeso/MacSCP)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## Key Features

1. **SSH Connection Manager (`~/.ssh/config`)**:
   - Automatically reads host configurations from `~/.ssh/config` and known hosts from `~/.ssh/known_hosts` on startup.
   - Real-time search filter by alias, host, or user.
   - Visual indicators for private keys (`🔑 id_rsa`), custom ports, and jumps (`🔀 ProxyJump`).
   - Add manual ad-hoc connections and reload the configuration at any time.

2. **Dual-Pane File Browser**:
   - **Left Panel**: Local macOS filesystem.
   - **Right Panel**: Remote SSH/SFTP server filesystem.
   - Smooth, draggable split divider with minimum width constraints.
   - Favorite bookmarks for quick navigation to frequently used directories.

3. **Seamless Remote Editing with Live Auto-Upload**:
   - Double-clicking any remote file downloads it to a secure cache directory (`~/Library/Caches/MacSCP/RemoteEdit/...`).
   - Automatically opens in **Nextpad++** (`/Applications/Nextpad++.app`) or your configured default editor.
   - A background filesystem monitor (`DispatchSourceFileSystemObject` with fallback polling) detects whenever you save (`Cmd + S`).
   - MacSCP instantly uploads the modified file back to the server and refreshes the remote file list.

4. **Sudo Elevation (SFTP Root Mode)**:
   - One-click elevation to superuser root privileges (`sudo /usr/lib/sftp-server` or `sudo /usr/libexec/sftp-server`) for modifying system files and permissions.
   - Distinctive visual banner and badges when operating in Sudo mode.

5. **In-Server Remote-to-Remote Copy**:
   - Right-click any remote file or folder > **"Copy to another location on server..."**.
   - Executes server-side (`cp -r`) via SSH instantly without consuming your local Mac's bandwidth.
   - **Recent Paths History**: Automatically remembers the last 10 destination paths for quick selection and reuse.

6. **Folder Creation & Directory Management**:
   - Dedicated "New Folder" buttons in both local and remote toolbars, context menus, and empty directory states.
   - Input validation against illegal characters (`/`, `:`, empty names).
   - Clear feedback and error handling (including permission denied alerts suggesting sudo elevation).

7. **Transfer Progress & Real-Time Metrics**:
   - Non-blocking asynchronous transfers.
   - Live metrics panel: transfer speed (MB/s or KB/s), percentage complete, elapsed time, and total bytes transferred.

8. **Path Navigation & Clipboard Utilities**:
   - Monospaced path headers with full breadcrumb display.
   - Right-click on any path bar to instantly copy the path to the clipboard.
   - Double-click path bar to directly type or edit absolute/relative paths.
   - Up-one-level (`..`) and refresh buttons.

9. **Multi-Language Support (Localization)**:
   - Built-in dynamic localization supporting English and Spanish.
   - Switch language on the fly via Settings (`Cmd + ,`) without restarting the app.

---

## Building from Source

### Requirements
- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (Swift 5.9+)

### Build with Xcode
1. Open the project in Xcode:
   ```bash
   open MacSCP.xcodeproj
   ```
2. Select **MacSCP** scheme and **My Mac** (or Any Mac).
3. Press **`Cmd + B`** to build or **`Cmd + R`** to run.

### Build via Command Line (Universal Release)
```bash
xcodebuild -project MacSCP.xcodeproj \
           -scheme MacSCP \
           -configuration Release \
           -destination 'generic/platform=macOS' \
           build
```

---

## Project Structure

```
MacScp/
├── MacSCP.xcodeproj/          # Xcode project configuration
│   └── project.pbxproj
├── Package.swift               # Swift Package Manager manifest
├── MacSCP/
│   ├── App/
│   │   └── MacSCPApp.swift     # Application entry point, AppVersion & About panel
│   ├── Models/
│   │   ├── SSHConnection.swift # SSH host connection model
│   │   ├── FileItem.swift      # Local & remote file metadata model
│   │   └── TransferProgress.swift # Transfer speed & progress calculations
│   ├── Services/
│   │   ├── SSHConfigParser.swift  # ~/.ssh/config reader & parser
│   │   ├── SFTPClient.swift       # Native SFTP client over SSH subsystem
│   │   ├── LocalFileManager.swift # Local filesystem manager
│   │   ├── FileWatchService.swift # Live filesystem watcher for remote editing
│   │   └── LocalizationService.swift # In-app language localization manager
│   ├── ViewModels/
│   │   └── AppViewModel.swift     # Central state coordinator & business logic
│   ├── Views/
│   │   ├── MainView.swift         # Main dual-panel layout & toolbar
│   │   ├── FileBrowserPanel.swift # Local/Remote file table & actions
│   │   ├── PathHeaderView.swift   # Breadcrumb path bar & actions
│   │   ├── ConnectionsSheet.swift # SSH connections selector & manager
│   │   ├── RemoteCopySheet.swift  # Server-side copy dialog with recent paths
│   │   ├── SettingsView.swift     # Preferences and language selection dialog
│   │   ├── TransferProgressView.swift # Transfer progress & speed banner
│   │   └── ToastBannerView.swift  # Floating notification banners
│   └── Resources/
│       ├── Info.plist             # Bundle properties & version metadata
│       ├── MacSCP.entitlements    # Subprocess execution entitlements
│       ├── AppIcon.icns           # High-resolution application icon
│       └── Assets.xcassets/       # Asset catalog
└── README.md
```

---

## Repository & Contributing

- **GitHub Repository**: [https://github.com/jcreyeso/MacSCP](https://github.com/jcreyeso/MacSCP)
- Issues, feedback, and pull requests are welcome!

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See the [LICENSE](LICENSE) file for details.
