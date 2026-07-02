import Foundation
import SwiftUI
import AppKit

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    // By default, checks a json file hosted on GitHub or another server
    @Published var updateJSONURL: String = "https://raw.githubusercontent.com/vertexnp/spotdock/main/update.json"
    
    @Published var isChecking: Bool = false
    @Published var isDownloading: Bool = false
    @Published var updateAvailable: Bool = false
    
    @Published var onlineVersion: String = ""
    @Published var downloadURL: String = ""
    @Published var releaseNotes: String = ""
    @Published var errorMessage: String? = nil
    @Published var successMessage: String? = nil
    
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    struct UpdateInfo: Codable {
        let version: String
        let downloadUrl: String
        let releaseNotes: String
    }
    
    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        errorMessage = nil
        successMessage = nil
        if !silent { isChecking = true }
        
        guard let url = URL(string: updateJSONURL) else {
            if !silent {
                errorMessage = "Invalid update URL."
                isChecking = false
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)
            
            let isNew = isVersion(updateInfo.version, newerThan: currentVersion)
            
            self.onlineVersion = updateInfo.version
            self.downloadURL = updateInfo.downloadUrl
            self.releaseNotes = updateInfo.releaseNotes
            self.updateAvailable = isNew
            self.isChecking = false
            
            if !silent && !isNew {
                successMessage = "SpotDock is up to date!"
            }
        } catch {
            self.isChecking = false
            if !silent {
                errorMessage = "Failed to check for updates: \(error.localizedDescription)"
            }
        }
    }
    
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let val1 = i < parts1.count ? parts1[i] : 0
            let val2 = i < parts2.count ? parts2[i] : 0
            if val1 > val2 { return true }
            if val1 < val2 { return false }
        }
        return false
    }
    
    func startAutomaticUpdate() async {
        guard !downloadURL.isEmpty, let url = URL(string: downloadURL) else {
            errorMessage = "Invalid download URL."
            return
        }
        
        isDownloading = true
        errorMessage = nil
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let zipURL = tempDir.appendingPathComponent("SpotDockUpdate.zip")
            
            // Delete old file if exists
            try? FileManager.default.removeItem(at: zipURL)
            
            // Download the file
            let (downloadedURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: downloadedURL, to: zipURL)
            
            // Unzip destination
            let extractDir = tempDir.appendingPathComponent("SpotDockUpdateExtract")
            try? FileManager.default.removeItem(at: extractDir)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
            
            // Unzip using ditto
            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-x", "-k", zipURL.path, extractDir.path]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()
            
            // Find the app bundle
            let appURL = extractDir.appendingPathComponent("SpotDock.app")
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                isDownloading = false
                errorMessage = "Downloaded ZIP did not contain SpotDock.app."
                return
            }
            
            // Overwrite and relaunch
            let oldAppPath = Bundle.main.bundlePath
            let newAppPath = appURL.path
            
            let script = """
            sleep 1
            rm -rf "\(oldAppPath)"
            mv "\(newAppPath)" "\(oldAppPath)"
            xattr -d com.apple.quarantine "\(oldAppPath)" 2>/dev/null || true
            open "\(oldAppPath)"
            """
            
            let updateProcess = Process()
            updateProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            updateProcess.arguments = ["-c", script]
            try updateProcess.run()
            
            // Quit current app so script can overwrite it
            NSApplication.shared.terminate(nil)
        } catch {
            isDownloading = false
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }
}
