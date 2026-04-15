import Foundation

class EnvironmentManager {
    static let shared = EnvironmentManager()
    private var env: [String: String] = [:]
    
    private init() {
        loadEnv()
    }
    
    private func loadEnv() {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil) else {
            // Fallback to searching in parent directories if not in bundle (for dev)
            let fileManager = FileManager.default
            let currentPath = fileManager.currentDirectoryPath
            let envPath = "\(currentPath)/.env"
            
            if let content = try? String(contentsOfFile: envPath) {
                parse(content)
            }
            return
        }
        
        if let content = try? String(contentsOfFile: path) {
            parse(content)
        }
    }
    
    private func parse(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[parts.count-1].trimmingCharacters(in: .whitespaces)
                env[key] = value
            }
        }
    }
    
    func get(_ key: String) -> String? {
        return env[key]
    }
}
