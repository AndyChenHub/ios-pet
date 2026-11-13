import BackgroundTasks
import Foundation
import SwiftUI

@main
struct IslandPupApp: App {
    static let bgRefreshIdentifier = "com.islandpup.app.refresh"

    @StateObject private var syncService = PairSyncService.shared
    @StateObject private var islandController = LiveActivityController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.configureAndRequestPermission()
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
                // Stop live HTTP stream & timers immediately on backgrounding to prevent radio/CPU drain.
                syncService.stopRealtimeListeners()
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
