import AppIntents
import Foundation

/// Triggered when tapping an action button inside the Expanded Dynamic Island or Lock Screen.
/// - If paired with another iPhone, sends `actionRaw` to set the partner's Dynamic Island pet!
/// - If unpaired (solo mode), updates this iPhone's own Dynamic Island pet animation.
public struct TriggerIslandPetActionIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Send Pet Action"
    public static var description = IntentDescription("Sets your paired partner's Dynamic Island pet action (or your own when solo).")
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
        if let action = PetAction(rawValue: actionRaw) {
            await PairSyncService.shared.handleDynamicIslandActionTap(action)
        }
        return .result()
    }
}

/// Pulls the latest action sent by the paired phone directly from the Dynamic Island or Lock Screen.
public struct SyncPartnerPetIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Sync Partner Pet"
    public static var description = IntentDescription("Syncs the latest pet action sent from your paired partner's phone.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await PairSyncService.shared.pollLatestMessages()
        await PairSyncService.shared.pushStateToActiveLiveActivities()
        return .result()
    }
}
