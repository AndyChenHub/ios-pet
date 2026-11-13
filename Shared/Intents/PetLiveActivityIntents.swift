import AppIntents
import Foundation

/// Triggered when tapping one of your quick action buttons inside the Expanded Dynamic Island or Lock Screen.
/// Updates YOUR pet's action on both your phone and your connected partner's phone!
public struct TriggerIslandPetActionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Set Pet Action"
    public static var description = IntentDescription("Updates your selected pet's Dynamic Island action across connected phones.")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Action Key")
    public var actionRaw: String

    public init() {
        self.actionRaw = PetAction.sleeping.rawValue
    }

    public init(action: PetAction) {
        self.actionRaw = action.rawValue
    }

    public func perform() async throws -> some IntentResult {
        if let action = PetAction.decodeKnown(from: actionRaw) {
            await PairSyncService.shared.handleDynamicIslandActionTap(action)
        }
        return .result()
    }
}

/// Pulls the latest pet action & message from your paired partner directly from the Dynamic Island or Lock Screen.
public struct SyncPartnerPetIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Sync Connected Pets"
    public static var description = IntentDescription("Syncs the latest pet action and message.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await PairSyncService.shared.pollLatestMessages()
        await PairSyncService.shared.pushStateToActiveLiveActivities()
        return .result()
    }
}
