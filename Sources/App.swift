import SwiftUI
import AppKit

@main
struct SleepPreventerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.sleepPrevented ? "bolt.fill" : "bolt.slash")
                .symbolRenderingMode(.hierarchical)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let sleepController = SleepController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.setSleepController(sleepController)

        // First reconciliation pass: clear any leaked disablesleep=1 from a prior crash.
        sleepController.forceAllowSleep(completion: nil)

        // Conditional second pass 2s later, in case an orphaned `sudo pmset 1`
        // from the prior crash is still in flight and flips state back to 1.
        // Skip if the user has started a timer during the 2s window.
        let bootGen = appState.startGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.appState.startGeneration == bootGen
                && !self.appState.isStarting
                && !self.appState.isRunning {
                self.sleepController.forceAllowSleep(completion: nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.cleanup()
    }
}

struct MenuContent: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headlineText)
                .font(.headline)
                .monospacedDigit()

            Text(subheadlineText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("+15 min") {
                    appState.addQuarterHour()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isStopping || (appState.errorMessage != nil && appState.isRunning))

                Button("Stop") {
                    appState.stop()
                }
                .buttonStyle(.bordered)
                .disabled(!appState.isRunning || appState.isStopping || appState.isStarting)
            }

            Divider()

            Button("GitHub") {
                if let url = URL(string: "https://github.com/stickerdaniel/sleep-preventer") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240)
    }

    private var headlineText: String {
        if appState.isStarting { return "Starting…" }
        if appState.isStopping { return "Stopping…" }
        if appState.isRunning { return Self.formatTime(appState.remainingSeconds) }
        return "Idle"
    }

    private var subheadlineText: String {
        if appState.isRunning && appState.isLidClosed {
            return "Lid closed — display off, system awake"
        }
        if appState.isRunning { return "Sleep prevented" }
        return "Normal sleep behavior"
    }

    static func formatTime(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
