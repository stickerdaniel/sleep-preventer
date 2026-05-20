import Foundation
import Observation

@Observable
final class AppState {
    var remainingSeconds: Int = 0
    var isRunning: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var sleepPrevented: Bool = false
    var isLidClosed: Bool = false
    var pendingSeconds: Int = 0
    var errorMessage: String? = nil
    var startGeneration: Int = 0

    private var sleepController: SleepController?
    private var lidMonitor: LidMonitor?
    private var tickTimer: Timer?

    private static let quarterHour: Int = 15 * 60

    init() {
        setupLidMonitor()
    }

    func setSleepController(_ controller: SleepController) {
        self.sleepController = controller
    }

    private func setupLidMonitor() {
        lidMonitor = LidMonitor()

        lidMonitor?.onLidClose = { [weak self] in
            guard let self = self else { return }
            self.isLidClosed = true
            if self.sleepPrevented {
                self.sleepController?.turnOffDisplay()
            }
        }

        lidMonitor?.onLidOpen = { [weak self] in
            self?.isLidClosed = false
        }

        isLidClosed = lidMonitor?.isLidClosed() ?? false
        lidMonitor?.start()
    }

    // MARK: - Public actions

    func addQuarterHour() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.isRunning {
                self.remainingSeconds += Self.quarterHour
                return
            }

            if self.isStarting {
                self.pendingSeconds += Self.quarterHour
                return
            }

            self.errorMessage = nil
            self.isStarting = true
            self.pendingSeconds = Self.quarterHour
            self.startGeneration &+= 1
            let gen = self.startGeneration

            self.sleepController?.preventSleep(true) { [weak self] success, errorOutput in
                guard let self = self else { return }

                if gen != self.startGeneration {
                    // Cancelled. Undo if pmset actually flipped to 1.
                    if success {
                        self.sleepController?.forceAllowSleep(completion: nil)
                    }
                    return
                }

                if success {
                    self.sleepPrevented = true
                    self.remainingSeconds = self.pendingSeconds
                    self.pendingSeconds = 0
                    self.isRunning = true
                    self.isStarting = false
                    self.startTickTimer()
                    if self.isLidClosed {
                        self.sleepController?.turnOffDisplay()
                    }
                } else {
                    self.isStarting = false
                    self.pendingSeconds = 0
                    self.errorMessage = "Couldn't disable sleep: \(errorOutput ?? "unknown error")"
                }
            }
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.isStopping else { return }

            self.isStopping = true
            self.invalidateTickTimer()
            self.remainingSeconds = 0

            self.sleepController?.preventSleep(false) { [weak self] success, errorOutput in
                guard let self = self else { return }
                if success {
                    self.sleepPrevented = false
                    self.isRunning = false
                    self.isStopping = false
                    self.errorMessage = nil
                    if self.isLidClosed {
                        self.sleepController?.sleepNow()
                    }
                } else {
                    self.isStopping = false
                    self.errorMessage = "Couldn't re-enable sleep: \(errorOutput ?? "unknown error"); click Stop to retry."
                }
            }
        }
    }

    func cleanup() {
        startGeneration &+= 1
        invalidateTickTimer()
        lidMonitor?.stop()
        sleepController?.forceAllowSleepSync()
    }

    // MARK: - Private

    private func startTickTimer() {
        invalidateTickTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func invalidateTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard isRunning else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        }
        if remainingSeconds <= 0 {
            handleExpiry()
        }
    }

    private func handleExpiry() {
        stop()
    }
}
