# IslandPup Backlog

## 1. Re-enable Custom Pet / Spritesheet Creation

**Current Status:** Disabled in UI (`FeatureFlags.enableCustomPetCreation = false`) so the roster focuses on the two built-in pets (**Alfie** & **Teddy**) and their 22 solo animations, 20 duo scenes, and 10 ultra-rare 3-act story skits.

### Preserved Infrastructure (Already Built & Ready)
All custom pet slicing, storage, E2EE pairing sync, and Dynamic Island rendering code remains intact in the codebase behind a single feature flag:
- `Shared/Models/PetModels.swift` — `FeatureFlags.enableCustomPetCreation` flag, `PetProfile` custom metadata, and `SpritesheetLayoutMode` (`8×9`, `8×18`, `4×4`, `1×4` horizontal strip, and single-sticker bounce).
- `Shared/Sync/CustomPetStore.swift` — Spritesheet auto-detection, frame slicing, App Group persistence, in-memory `NSCache`, and `loadRoster()` filtering.
- `Shared/Models/MicroSpriteCodec.swift` — Compressed micro-sprite codec for syncing custom pets across paired iPhones and rendering within ActivityKit's `4 KB` Live Activity payload budget.
- `IslandPup/Views/AddPetSheet.swift` — Full Photos & Files spritesheet importer UI with live animated frame preview (currently still used in `.editExisting` mode for renaming and recoloring Alfie & Teddy).
- `IslandPup/Views/ContentView.swift` — Top-left `"New Pet"` toolbar button and `"Add Sheet / Create New Pet"` roster card, gated by `FeatureFlags.enableCustomPetCreation`.

### How to Restore It Later
1. Open `Shared/Models/PetModels.swift` and flip:
   ```swift
   enum FeatureFlags {
       static let enableCustomPetCreation: Bool = true
   }
   ```
2. Build & run — the `"New Pet"` toolbar button, horizontal scrolling pet roster, `"Add Sheet"` card, and previously saved custom pets will reappear automatically.

### Optional Future Enhancements When Re-enabling
- Support importing updated v2 sheets covering all 14 Emotions & Tasks + 8 Quirks (or graceful fallback mapping to core rows).
- Allow custom pets to participate in side-by-side duo interactions when paired with Alfie, Teddy, or another custom pet.
