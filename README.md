# IslandPup — Paired Dynamic Island Pet for iPhone 🐶🐾

**IslandPup** puts an animated companion (**Alfie** the Chibi Terrier or **Teddy** the Scruffy Schnauzer) right onto your iPhone's **Dynamic Island** and **Lock Screen**, and lets **two iPhones pair together** so Phone 1 can remotely change Phone 2's pet animation (for example, setting the other phone's pet to **Sleeping 💤**, **Waving 👋**, **Jumping 🎉**, or **Working 💻**) and vice versa!

---

## ✨ Features

- **1 Active Pet on Your Dynamic Island**: Pick either **Alfie** or **Teddy** at any time—renders in full color across **Compact**, **Minimal**, **Expanded Dynamic Island**, and **Lock Screen** Live Activity views.
- **Zero-Battery Continuous Dynamic Island Animation**: Uses a custom 1.3 KB OpenType GSUB gate font (`Shared/Resources/PetTimerGate.ttf`) combined with dual fractional `Text(..., style: .timer)` masks so all 10 animations loop smoothly on the Dynamic Island & Lock Screen using 100% public Apple APIs and zero background CPU drain (automatically settling into a peaceful static pose on Always-On Display).
- **Phone-to-Phone Remote Pet Control (End-to-End Encrypted)**:
  - Generate an 8-character **Pair Code** on Phone 1 and enter it on Phone 2 (messages are end-to-end encrypted & authenticated with `AES-256-GCM` over HTTPS; zero account signup or backend configuration needed).
  - Tap any of the **10 animations** (`Idle`, `Sleeping`, `Waving`, `Jumping`, `Trot Right`, `Trot Left`, `Waiting`, `Working`, `Reading`, `Dizzy`) + optional short note to update the other phone's Dynamic Island pet!
  - Long-press your Dynamic Island (`Expanded` view) to send `💤 Sleep`, `👋 Wave`, `🎉 Jump`, or `💻 Work` to your partner's Island without even opening the app (`LiveActivityIntent`).
- **Desktop / Browser Companion (`WebCompanion/index.html`)**: Preview Alfie & Teddy inside an interactive Dynamic Island simulator right on Windows/macOS, or enter the same 8-character Pair Code to test remote pairing directly with an iPhone!

---

## 📦 Building & Installing on iPhone

### Option A: From Windows (GitHub Actions `.ipa` + Sideloading)
1. Push this repository to GitHub (`main` branch).
2. Open the **Actions** tab on GitHub → **Build IslandPup iOS IPA** (`.github/workflows/build-ipa.yml`).
3. Download the **`IslandPup-iOS-IPA`** artifact (`IslandPup.ipa`).
4. Install `IslandPup.ipa` onto both iPhones using **SideStore**, **AltStore**, or **Sideloadly** with your Apple ID.
   - *Note*: Live Activities (`NSSupportsLiveActivities`) use `pushType: nil` and fallback storage so they work out of the box even with free Apple IDs!

### Option B: On a Mac with Xcode 15 / 16+
1. Open `IslandPup.xcodeproj` directly in Xcode (or run `xcodegen generate` if modifying `project.yml`).
2. In **Signing & Capabilities**, select your Apple ID / Team for both **`IslandPup`** and **`IslandPupWidgetExtension`** (and customize the Bundle Identifier prefix if needed).
3. Select your iPhone (iPhone 14 Pro / 15 / 16 / 17 or newer with Dynamic Island, iOS 17.0+) and press **Cmd + R**.

---

## 🛠 Regenerating Sprite Assets & Timer Gate Font

If you ever tweak `Sprites/Alfie/spritesheet.png` or `Sprites/Teddy/spritesheet.png`:

```bash
pip install pillow fonttools uharfbuzz
python Scripts/generate_assets.py
```

This slices all 122 lossless `@3x` frames into `Shared/Assets.xcassets`, generates the `1024×1024` `AppIcon`, rebuilds `Shared/Resources/PetTimerGate.ttf`, and runs HarfBuzz OpenType shaping verification across all frame counts.
