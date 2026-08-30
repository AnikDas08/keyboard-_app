# Ananse Stroke Book — iOS Keyboard Extension

A native iOS custom keyboard that uses the head + stroke compose model from the
web prototype. **This must be built on a Mac with Xcode** — it cannot be built or
run on Replit.

## What's here

```
ios/
├── project.yml                 XcodeGen spec (app + keyboard extension targets)
├── App/                        Minimal host app (enable + try the keyboard)
│   ├── AnanseApp.swift
│   ├── ContentView.swift
│   └── Info.plist
├── Keyboard/                   The keyboard extension
│   ├── Ananse.swift            Data model + compose engine (single source of truth)
│   ├── KeyboardViewController.swift   UIInputViewController, builds the keys
│   ├── AnanseFont.swift        Registers the bundled .ttf fonts
│   └── Info.plist              NSExtension keyboard configuration
└── Shared/Fonts/               One bundled font per glyph style
    ├── AnanseStrokeBookNew.ttf        "New" (default)
    ├── AnanseStrokeBook.ttf           "Classic"
    └── AnanseStrokeBook{Bow,Fork,Wave,Cup,Triangle,Circle}.ttf
```

Distributing test builds to iPhones through TestFlight: see **TESTFLIGHT.md**
in this folder.

## Requirements

- macOS with **Xcode 15+**
- An **Apple Developer account** (free works for on-device testing; paid $99/yr for App Store and TestFlight)
- [XcodeGen](https://github.com/yonyz/XcodeGen) to generate the project: `brew install xcodegen`

## Build & run

```bash
cd native/ios
xcodegen generate          # creates AnanseKeyboard.xcodeproj
open AnanseKeyboard.xcodeproj
```

In Xcode:
1. Select the **AnanseApp** scheme and set your **Signing Team** on both targets
   (AnanseApp and AnanseKeyboard).
2. Run on a device or simulator.
3. Enable the keyboard: **Settings → General → Keyboard → Keyboards → Add New
   Keyboard… → Ananse Keyboard**.
4. In any text field, tap 🌐 to switch to it.

### App Group (preview follows the keyboard's settings)

Both targets declare the **`group.app.ananse.keyboard`** App Group
(`project.yml` → `entitlements`). It lets the host app's "Try it" preview read
the glyph style and hanging-line weight the keyboard extension saves, so the
preview mirrors whatever you dial in on the keyboard — the same behaviour as
the Android host app.

- The group ID must be registered under **your** Apple Developer team
  (developer.apple.com → Certificates, Identifiers & Profiles → Identifiers →
  App Groups) and enabled for both bundle IDs. With automatic signing, Xcode
  usually does this for you once a team is set.
- If you rename the group, change it in **three** places: `project.yml`,
  `Keyboard/KeyboardViewController.swift` (`appGroupID`), and
  `App/ContentView.swift` (`appGroupID`).
- If the group isn't configured, everything still works: the preview falls
  back to the "New" glyph design and shows its own hanging-line picker.

The host app's "Try it" field remembers what you typed between launches (like
the web app's draft persistence); clearing the field also clears the stored
draft.

## How it works

Two layouts, toggled by the utility-row layout key:

- **Strokes** (compose board):
  - **Tap a family head** (A / M / N / G) to select that family; the stroke row
    then composes letters from it.
  - **Long-press a head** to type the family's root/shell letter.
  - **Tap a stroke** to type the composed letter.
- **QWERTY**: the standard 10/9/7 key order; each key shows the Ananse
  symbol(s) that write its letter and types the resolved output (C types S,
  Q types KW).

The **style key** cycles the glyph design drawing the keys (New, Classic, Bow,
Fork, Wave, Cup, Triangle, Circle) — each backed by a bundled font.

The **‾ hanging-line key** cycles the Ananse Hanging Line drawn over the key
glyphs: Off → Thin → Medium → Thick. The weights use the same em factors as
the web keyboard (0.042 / 0.084 / 0.126 of the glyph size), the line is
centered on the head-top level (0.645em above the baseline), and the choice is
remembered in UserDefaults.

- Inserted text is standard **Latin letters** (Q is inserted as `KW`). The keys
  themselves show Ananse glyphs via the bundled font. To see Ananse glyphs in the
  text of *other* apps, the AnanseStrokeBook font must be installed system-wide —
  this is an inherent limitation of how keyboard extensions work (they insert
  characters, not custom glyphs).

## Extending

- Add a numbers/symbols layer and emoji by adding more rows in
  `KeyboardViewController.buildKeyboard()`.
- The compose data lives entirely in `Ananse.swift` — keep it in sync with the web
  app's `src/data/ananse.ts` if the writing model changes.
