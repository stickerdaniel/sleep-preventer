import Foundation
import IOKit.pwr_mgt

final class SleepController {
    private var sleepPrevented = false
    private let serialQueue = DispatchQueue(label: "dev.sticker.sleep-preventer.pmset", qos: .userInitiated)
    private var displayAssertion: IOPMAssertionID = IOPMAssertionID(0)
    private var hasDisplayAssertion = false

    func preventSleep(_ prevent: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard prevent != sleepPrevented else {
            DispatchQueue.main.async { completion(true, nil) }
            return
        }

        let value = prevent ? "1" : "0"
        runPmset(args: ["-a", "disablesleep", value]) { [weak self] success, errorOutput in
            if success {
                self?.sleepPrevented = prevent
                if prevent {
                    self?.acquireDisplayAssertion()
                } else {
                    self?.releaseDisplayAssertion()
                }
            }
            DispatchQueue.main.async { completion(success, errorOutput) }
        }
    }

    /// Bypasses the `preventSleep` guard. Always runs `sudo -n pmset -a disablesleep 0`.
    /// Used for boot reconciliation and the start-cancellation undo path.
    func forceAllowSleep(completion: ((Bool, String?) -> Void)? = nil) {
        runPmset(args: ["-a", "disablesleep", "0"]) { [weak self] success, errorOutput in
            if success {
                self?.sleepPrevented = false
                self?.releaseDisplayAssertion()
            }
            DispatchQueue.main.async { completion?(success, errorOutput) }
        }
    }

    /// Synchronous variant for `applicationWillTerminate`. Uses `serialQueue.sync`
    /// so it blocks behind any in-flight `preventSleep(true)` and runs `pmset 0` last.
    func forceAllowSleepSync() {
        serialQueue.sync {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    self.sleepPrevented = false
                }
            } catch {
                // Best effort — process exit imminent.
            }
            self.releaseDisplayAssertionLocked()
        }
    }

    // MARK: - Display sleep assertion

    /// Caller must be on serialQueue.
    private func acquireDisplayAssertion() {
        guard !hasDisplayAssertion else { return }
        var id: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Sleep Preventer timer active" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            displayAssertion = id
            hasDisplayAssertion = true
        }
    }

    /// Caller must be on serialQueue.
    private func releaseDisplayAssertion() {
        releaseDisplayAssertionLocked()
    }

    /// Same as releaseDisplayAssertion but expects caller already inside serialQueue.sync.
    private func releaseDisplayAssertionLocked() {
        guard hasDisplayAssertion else { return }
        IOPMAssertionRelease(displayAssertion)
        displayAssertion = IOPMAssertionID(0)
        hasDisplayAssertion = false
    }

    func sleepNow() {
        serialQueue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = ["-n", "/usr/bin/pmset", "sleepnow"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    func turnOffDisplay() {
        serialQueue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["displaysleepnow"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// Reads the real system-wide `SleepDisabled` flag via `pmset -g` (no sudo needed).
    /// Ground truth, independent of the in-memory `sleepPrevented` mirror — catches
    /// drift from external `pmset` calls or a crashed prior process.
    func readSystemSleepDisabled() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]

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
        for line in output.split(separator: "\n") where line.contains("SleepDisabled") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return parts.last == "1"
        }
        return false
    }

    /// Whether the app currently holds the display-sleep IOKit assertion. Thread-safe.
    var isDisplayAssertionHeld: Bool {
        serialQueue.sync { hasDisplayAssertion }
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

    private func runPmset(args: [String], completion: @escaping (Bool, String?) -> Void) {
        serialQueue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = ["-n", "/usr/bin/pmset"] + args

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if task.terminationStatus == 0 {
                    completion(true, nil)
                } else {
                    completion(false, output.isEmpty ? "pmset exited \(task.terminationStatus)" : output)
                }
            } catch {
                completion(false, error.localizedDescription)
            }
        }
    }
}
