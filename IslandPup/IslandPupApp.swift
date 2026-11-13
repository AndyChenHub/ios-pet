import BackgroundTasks
import Foundation
import SwiftUI
import UIKit

@main
struct IslandPupApp: App {
    static let bgRefreshIdentifier = "com.islandpup.app.refresh"

    @StateObject private var syncService = PairSyncService.shared
    @StateObject private var islandController = LiveActivityController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.configureAndRequestPermission()
        PairSyncService.shared.beginBackgroundWork = { onExpire in
            final class TaskBox: @unchecked Sendable {
                private let lock = NSLock()
                private var identifier: UIBackgroundTaskIdentifier = .invalid

                func setIdentifier(_ id: UIBackgroundTaskIdentifier) {
                    lock.lock()
                    identifier = id
                    lock.unlock()
                }

                func takeIdentifier() -> UIBackgroundTaskIdentifier {
                    lock.lock()
                    defer { lock.unlock() }
                    let current = identifier
                    identifier = .invalid
                    return current
                }
            }

            let box = TaskBox()
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "IslandPupSync") {
                let idToEnd = box.takeIdentifier()
                Task { @MainActor in
                    onExpire()
                    if idToEnd != .invalid {
                        UIApplication.shared.endBackgroundTask(idToEnd)
                    }
                }
            }
            guard taskID != .invalid else { return nil }
            box.setIdentifier(taskID)

            return BackgroundWorkToken {
                let idToEnd = box.takeIdentifier()
                guard idToEnd != .invalid else { return }
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(idToEnd)
                }
            }
        }
        Self.registerBackgroundRefresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                syncService: syncService,
                islandController: islandController
            )
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                islandController.refreshActiveStatus()
                Task {
                    await syncService.handleAppBecameActive()
                }

            case .background:
                // Keep the lightweight SSE listener alive during iOS's Home Screen background grace window
                // so swiping up to watch the Dynamic Island receives partner updates and synced animations live.
                syncService.enterBackgroundStreamGracePeriod()
                if SharedStorage.shared.isPaired && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                    Self.scheduleBackgroundRefresh()
                } else {
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgRefreshIdentifier)
                }

            case .inactive:
                break

            @unknown default:
                break
            }
        }
    }

    private static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            if SharedStorage.shared.isPaired && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                scheduleBackgroundRefresh()
            }

            let workTask = Task { @MainActor in
                if SharedStorage.shared.isPaired {
                    await PairSyncService.shared.pollLatestMessages()
                }
                refreshTask.setTaskCompleted(success: true)
            }

            refreshTask.expirationHandler = {
                workTask.cancel()
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
