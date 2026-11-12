import BackgroundTasks
import UIKit

/// Keeping the library scan going outside the foreground. There is one scan engine (CleanerLibrary.scan); these only
/// keep the process alive, show progress, and stop it cleanly (the scan checkpoints, and the next scan resumes).
///
/// Info.plist needs (the host app's bundle id in place of <bundle>):
/// - BGTaskSchedulerPermittedIdentifiers: `<bundle>.scan.*` (continued-processing tasks, iOS 26+) and `<bundle>.scan-overnight`
/// - UIBackgroundModes: `processing` (for the overnight BGProcessingTask)
/// and the app calls `CleanerBackground.registerOvernightScan()` before it finishes launching.
enum CleanerBackground {
    static var overnightID: String { Bundle.main.bundleIdentifier! + ".scan-overnight" }
    @MainActor static var overnightRegistered = false // submitting an unregistered id would crash the app when it fires

    /// Registers the overnight scan: on external power, iOS may launch the app in the background to finish a scan.
    @MainActor static func registerOvernightScan() {
        overnightRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: overnightID, using: .main) { task in
            MainActor.assumeIsolated {
                // Launched in the background, no UI: a library of its own on the same cache file.
                // shortcut: if the user opens the app meanwhile, its scan runs alongside; both write whole, valid caches.
                let library = CleanerLibrary()
                task.expirationHandler = { Task { @MainActor in library.stopScan() } } // called on a background queue
                Task {
                    await library.scan()
                    task.setTaskCompleted(success: !library.isUnfinished)
                }
            }
        }
    }
}

extension CleanerLibrary {
    /// Starts keeping the scan alive; call the result with whether the scan finished, when it ends.
    /// - every iOS: a UIKit background-task assertion, so leaving the app checkpoints instead of losing work;
    /// - iOS 26+, for a long scan (a full pass) started in the foreground: a continued-processing task with system progress UI;
    /// - an overnight BGProcessingTask (external power) while the scan stays unfinished.
    func keepScanAlive(long: Bool) -> (_ finished: Bool) -> Void {
        let app = UIApplication.shared
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = app.beginBackgroundTask(withName: "Library scan") { [weak self] in
            // iOS 26's continued-processing task outlives this assertion and has its own expiry; otherwise stop now. The
            // scanner saves on its way out; checkpoints every 3 s cover a hard stop.
            if self?.continuedTask == nil { self?.stopScan() }
            app.endBackgroundTask(assertion)
            assertion = .invalid
        }
        if long, app.applicationState != .background, #available(iOS 26.0, *) { submitContinuedScan() } // at launch the app is still .inactive
        scheduleOvernightScan(true)
        return { [weak self] finished in
            if #available(iOS 26.0, *), let task = self?.continuedTask as? BGContinuedProcessingTask {
                task.progress.completedUnitCount = finished ? task.progress.totalUnitCount : task.progress.completedUnitCount
                task.setTaskCompleted(success: finished)
            }
            self?.continuedTask = nil
            self?.scheduleOvernightScan(!finished)
            if assertion != .invalid { app.endBackgroundTask(assertion) }
            assertion = .invalid
        }
    }

    func reportBackgroundProgress(_ text: String, _ fraction: Double) {
        guard #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask else { return }
        task.progress.completedUnitCount = Int64(fraction * Double(task.progress.totalUnitCount))
        task.updateTitle(task.title, subtitle: text)
    }

    /// A one-off identifier per scan under `<bundle>.scan.*`, registered just before submitting: iOS doesn't route
    /// wildcard handlers, and registering the same identifier twice kills the app.
    @available(iOS 26.0, *)
    private func submitContinuedScan() {
        let id = Bundle.main.bundleIdentifier! + ".scan." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { return }
                guard let self, self.isScanning else { return task.setTaskCompleted(success: true) }
                task.progress.totalUnitCount = 1000
                task.expirationHandler = { [weak self] in Task { @MainActor in self?.stopScan() } } // called on a background queue
                self.continuedTask = task
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Scanning your photo library", subtitle: "Starting…")
        request.strategy = .fail // now or never: a queued start after the scan ended would show stale progress
        try? BGTaskScheduler.shared.submit(request)
    }

    private func scheduleOvernightScan(_ wanted: Bool) {
        guard CleanerBackground.overnightRegistered else { return }
        if wanted {
            let request = BGProcessingTaskRequest(identifier: CleanerBackground.overnightID)
            request.requiresExternalPower = true
            try? BGTaskScheduler.shared.submit(request)
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: CleanerBackground.overnightID)
        }
    }
}
