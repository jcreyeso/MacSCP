import Foundation

/// Service to parse OpenSSH configuration from ~/.ssh/config and ~/.ssh/known_hosts.
public final class SSHConfigParser {
    
    /// Default location of SSH config file.
    public static var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ssh/config")
    }
    
    /// Default location of known_hosts file.
    public static var knownHostsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ssh/known_hosts")
    }
    
    /// Reads and parses all defined SSH connections from ~/.ssh/config.
    public static func loadConnections() -> [SSHConnection] {
        var connections: [SSHConnection] = []
        
        let path = configURL.path
        if FileManager.default.fileExists(atPath: path) {
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                connections.append(contentsOf: parse(configText: content))
            } catch {
                print("Error reading ~/.ssh/config: \(error.localizedDescription)")
            }
        }
        
        // Also check ~/.ssh/known_hosts to supplement if user has empty config
        if connections.isEmpty {
            let hostsFromKnown = parseKnownHosts()
            connections.append(contentsOf: hostsFromKnown)
        }
        
        return connections
    }
    
    /// Parses OpenSSH config syntax into SSHConnection objects.
    public static func parse(configText: String) -> [SSHConnection] {
        var results: [SSHConnection] = []
        let lines = configText.components(separatedBy: .newlines)
        
        var currentAliases: [String] = []
        var currentHostName = ""
        var currentUser = ""
        var currentPort = 22
        var currentIdentityFile: String? = nil
        var currentProxyJump: String? = nil
        
        func flushCurrent() {
            guard !currentAliases.isEmpty else { return }
            for alias in currentAliases {
                // Ignore wildcard global patterns like Host * or Host ?
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == "*" || trimmed.contains("*") || trimmed.contains("?") {
                    continue
                }
                
                let conn = SSHConnection(
                    alias: trimmed,
                    hostName: currentHostName.isEmpty ? trimmed : currentHostName,
                    user: currentUser,
                    port: currentPort,
                    identityFile: currentIdentityFile,
                    proxyJump: currentProxyJump,
                    isManual: false
                )
                results.append(conn)
            }
            
            // Reset state
            currentAliases = []
            currentHostName = ""
            currentUser = ""
            currentPort = 22
            currentIdentityFile = nil
            currentProxyJump = nil
        }
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            
            // Tokens can be separated by spaces or tabs or '='
            let scanner = Scanner(string: line)
            guard let key = scanner.scanUpToString(" ")?.trimmingCharacters(in: .whitespaces) else {
                continue
            }
            
            let remainder = line.dropFirst(key.count).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "=")))
            
            let lowerKey = key.lowercased()
            if lowerKey == "host" {
                flushCurrent()
                // Host can be followed by multiple space-separated aliases
                let tokens = remainder.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                currentAliases = tokens
            } else if !currentAliases.isEmpty {
                switch lowerKey {
                case "hostname":
                    currentHostName = remainder
                case "user":
                    currentUser = remainder
                case "port":
                    if let p = Int(remainder) {
                        currentPort = p
                    }
                case "identityfile":
                    currentIdentityFile = remainder
                case "proxyjump":
                    currentProxyJump = remainder
                default:
                    break
                }
            }
        }
        
        flushCurrent()
        return results
    }
    
    /// Parses host names from ~/.ssh/known_hosts if available.
    public static func parseKnownHosts() -> [SSHConnection] {
        let path = knownHostsURL.path
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var seen = Set<String>()
            var hosts: [SSHConnection] = []
            
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
                
                // First field contains host or [host]:port
                let parts = trimmed.components(separatedBy: .whitespaces)
                guard let hostPart = parts.first else { continue }
                
                // Skip hashed hosts like |1|...
                if hostPart.hasPrefix("|1|") { continue }
                
                let hostEntries = hostPart.components(separatedBy: ",")
                for rawEntry in hostEntries {
                    var host = rawEntry
                    var port = 22
                    
                    if host.hasPrefix("[") && host.contains("]:") {
                        let subparts = host.components(separatedBy: "]:")
                        if let h = subparts.first?.dropFirst(), let p = subparts.last, let pInt = Int(p) {
                            host = String(h)
                            port = pInt
                        }
                    }
                    
                    if !host.isEmpty && !seen.contains(host) && !host.contains("*") {
                        seen.insert(host)
                        hosts.append(SSHConnection(
                            alias: host,
                            hostName: host,
                            user: "",
                            port: port,
                            isManual: false
                        ))
                    }
                }
            }
            return hosts
        } catch {
            return []
        }
    }
}

