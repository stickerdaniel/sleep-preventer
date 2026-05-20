import Foundation
import IOKit

class LidMonitor {
    private var timer: Timer?
    private var lastLidState: Bool = false
    
    var onLidClose: (() -> Void)?
    var onLidOpen: (() -> Void)?
    
    func start() {
        // Get initial state
        lastLidState = isLidClosed()
        
        // Poll for lid state changes every 2 seconds
        // (IOKit notifications for clamshell state are complex and unreliable)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkLidState()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkLidState() {
        let currentState = isLidClosed()
        
        if currentState != lastLidState {
            lastLidState = currentState
            
            DispatchQueue.main.async { [weak self] in
                if currentState {
                    self?.onLidClose?()
                } else {
                    self?.onLidOpen?()
                }
            }
        }
    }
    
    func isLidClosed() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-r", "-k", "AppleClamshellState", "-d", "4"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("\"AppleClamshellState\" = Yes")
    }
}
