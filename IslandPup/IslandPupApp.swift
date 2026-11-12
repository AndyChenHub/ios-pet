import BackgroundTasks
import SwiftUI
import UIKit

@MainActor
private final class AppLifecycleCoordinator {
    static let shared = AppLifecycleCoordinator()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func beginGraceBackgroundTask() {
        endGraceBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "IslandPupPairSync") { [weak self] in
            Task { @MainActor in
                PairSyncService.shared.stopRealtimeListeners()
                self?.endGraceBackgroundTask()
            }
        }
    }

    func endGraceBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}

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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                AppLifecycleCoordinator.shared.endGraceBackgroundTask()
                islandController.refreshActiveStatus()
                if SharedStorage.shared.isPaired {
                    syncService.startRealtimeListeners()
                    Task {
                        await syncService.pollLatestMessages()
                    }
                }

            case .background:
                if SharedStorage.shared.isPaired {
                    Self.scheduleBackgroundRefresh()
                    AppLifecycleCoordinator.shared.beginGraceBackgroundTask()
                } else {
                    syncService.stopRealtimeListeners()
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
            scheduleBackgroundRefresh()

            let workTask = Task { @MainActor in
                await PairSyncService.shared.pollLatestMessages()
                await PairSyncService.shared.pushStateToActiveLiveActivities()
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
