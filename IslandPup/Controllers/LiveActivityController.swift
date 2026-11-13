import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()

    @Published private(set) var isRunningOnIsland: Bool = false
    @Published var statusError: String?

    private init() {
        refreshActiveStatus()
    }

    func refreshActiveStatus() {
        isRunningOnIsland = !Activity<PetActivityAttributes>.activities.isEmpty
    }

    func toggleIsland(with state: PetActivityAttributes.ContentState) async {
        if isRunningOnIsland {
            await stopIsland()
        } else {
            await startIsland(with: state)
        }
    }

    func startIsland(with state: PetActivityAttributes.ContentState) async {
        statusError = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusError = "Live Activities are turned off. Enable them in Settings → IslandPup → Live Activities."
            return
        }

        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        do {
            let safeState = state.fittingActivityKitBudget()
            let staleDate = safeState.activeInteraction.map { Date(timeIntervalSince1970: $0.expiresAt) }
            let attributes = PetActivityAttributes()
            let content = ActivityContent(state: safeState, staleDate: staleDate)
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            PairSyncService.shared.recordPushedState(safeState)
            isRunningOnIsland = true
        } catch {
            statusError = "Couldn't start Dynamic Island pet: \(error.localizedDescription)"
            refreshActiveStatus()
        }
    }

    func stopIsland() async {
        for activity in Activity<PetActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        PairSyncService.shared.recordPushedState(nil)
        isRunningOnIsland = false
    }
}
