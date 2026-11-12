# IslandPup — Paired Two-Dog Dynamic Island Pet for iPhone 🐶🐾

**IslandPup** brings an animated pet companion (**Alfie**, **Teddy**, or **any custom pet you create by importing a spritesheet**) onto your iPhone's **Dynamic Island** and **Lock Screen**. When **two iPhones connect**, **both dogs live together on the Dynamic Island**, setting your pet's action & message updates both phones and delivers your message in your partner's notifications, and the two dogs occasionally surprise you with **rare interactions** together!

---

## ✨ Features

- **Select, Name & Create Custom Pets**:
  - Pick **Alfie** or **Teddy**, or tap **New Pet / Add Sheet** to import any PNG spritesheet from **Photos** or **Files** (`8×9` standard sheet, `4×4` grid, `4-frame` strip, or single dog sticker).
  - **Name or rename** any pet and pick its Dynamic Island theme color.
- **Own Your Pet — Sync Across Both Phones**:
  - Set **your pet's action** (`Idle`, `Sleeping`, `Waving`, `Jumping`, `Trot Right`, `Trot Left`, `Waiting`, `Working`, `Reading`, `Dizzy`) and an optional message.
  - Automatically updates your own Dynamic Island **and** syncs end-to-end encrypted (`AES-256-GCM`) to your connected partner's phone—including custom spritesheet pets via ultra-compact zlib-compressed 16-color micro-sprites (`< 1 KB`).
- **Both Dogs on the Dynamic Island & Partner Notification Messages**:
  - When connected, **both dogs** animate side-by-side on the **Compact Dynamic Island** (`compactLeading` + `compactTrailing`), **Expanded Dynamic Island**, and **Lock Screen Live Activity**.
  - Incoming partner updates display **your partner's message** both as an iOS **Notification** banner/card and inside the Lock Screen Live Activity & Expanded Dynamic Island.
- **Rare Spontaneous Two-Dog Interactions ✨**:
  - While connected, the two dogs randomly trigger synchronized rare moments together (**Nose Boop 💖**, **Play Zoomies 🐾✨**, **Puppy Dance 🎉✨**, and **Snuggle Nap 💕💤**) across both phones!
- **Desktop / Browser Companion (`WebCompanion/index.html`)**:
  - Test two-dog Dynamic Island pairing, custom pet naming, partner notifications, and `v3` `AES-256-GCM` sync directly from a browser tab alongside your iPhone.

---

## 📦 Building & Installing on iPhone

### Option A: From Windows (GitHub Actions `.ipa` + Sideloading)
1. Push this repository to GitHub (`main` branch).
2. Open the **Actions** tab on GitHub → **Build IslandPup iOS IPA** (`.github/workflows/build-ipa.yml`).
3. Download the **`IslandPup-iOS-IPA`** artifact (`IslandPup.ipa`).
4. Install `IslandPup.ipa` onto your iPhone(s) using **SideStore**, **AltStore**, or **Sideloadly** with your Apple ID.
   - *Important for Sideloadly / AltStore*: Leave **"Remove App Extensions (PlugIns)" UNCHECKED** (and click *Keep App Extensions* in AltStore/SideStore) so `IslandPupWidgetExtension` is installed—otherwise iOS cannot render the dogs inside the Dynamic Island!
   - *Tip*: Once IslandPup shows your pet is live, **swipe up to the Home Screen** (iOS hides an app's own Live Activity while that app itself is open in the foreground).

### Option B: On a Mac with Xcode 16+
1. Open `IslandPup.xcodeproj` directly in Xcode (or run `xcodegen generate` if modifying `project.yml`).
2. In **Signing & Capabilities**, select your Apple ID / Team for both **`IslandPup`** and **`IslandPupWidgetExtension`**.
3. Select your iPhone (iPhone 14 Pro / 15 / 16 / 17 or newer with Dynamic Island, iOS 17.0+) and press **Cmd + R**.

---

## 🛠 Regenerating Bundled Sprite Assets & Timer Gate Font

```bash
pip install pillow fonttools uharfbuzz
python Scripts/generate_assets.py
python Scripts/generate_xcodeproj.py
```
