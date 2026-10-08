import Foundation

/// Represents an SSH connection profile, parsed from ~/.ssh/config or added manually.
public struct SSHConnection: Identifiable, Hashable, Codable {
    public var id: UUID
    public var alias: String
    public var hostName: String
    public var user: String
    public var port: Int
    public var identityFile: String?
    public var proxyJump: String?
    public var isManual: Bool
    public var useSudoSFTP: Bool
    
    public init(
        id: UUID = UUID(),
        alias: String,
        hostName: String = "",
        user: String = "",
        port: Int = 22,
        identityFile: String? = nil,
        proxyJump: String? = nil,
        isManual: Bool = false,
        useSudoSFTP: Bool = false
    ) {
        self.id = id
        self.alias = alias
        self.hostName = hostName.isEmpty ? alias : hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.isManual = isManual
        self.useSudoSFTP = useSudoSFTP
    }
    
    /// User-friendly label for the connection.
    public var displayTitle: String {
        return alias
    }
    
    /// Target address description (e.g. user@host:port).
    public var displaySubtitle: String {
        var str = ""
        if !user.isEmpty {
            str += "\(user)@"
        }
        str += hostName.isEmpty ? alias : hostName
        if port != 22 {
            str += ":\(port)"
        }
        return str
    }
    
    /// Effective SSH target destination for command execution.
    public var destinationString: String {
        if !user.isEmpty && !alias.contains("@") && alias != hostName {
            return "\(user)@\(hostName)"
        } else if !user.isEmpty && !alias.contains("@") {
            return "\(user)@\(alias)"
        } else {
            return alias
        }
    }
}

