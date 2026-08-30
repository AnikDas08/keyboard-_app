# Distributing the iPhone build through TestFlight

TestFlight is Apple's official testing channel: testers install the current
build from the TestFlight app and get updates automatically. The archive and
upload steps must run on a Mac with Xcode — Apple provides no other way to
sign and upload an iOS build.

## Prerequisites

- macOS with **Xcode 15+**
- A **paid Apple Developer Program membership** ($99/yr) — free accounts
  cannot use TestFlight
- [XcodeGen](https://github.com/yonatankarni/XcodeGen): `brew install xcodegen`

## One-time setup (App Store Connect)

1. **Identifiers** — at developer.apple.com → Certificates, Identifiers &
   Profiles → Identifiers, register:
   - App ID `app.ananse.keyboard` (the host app)
   - App ID `app.ananse.keyboard.extension` (the keyboard extension)
   - App Group `group.app.ananse.keyboard`, enabled for **both** App IDs
     (with automatic signing, Xcode can also do this once a team is set)
2. **App record** — at appstoreconnect.apple.com → My Apps → **+** → New App,
   using bundle ID `app.ananse.keyboard`.
3. **Testers** — in the app's TestFlight tab, create an **Internal Testing**
   group and add testers by their Apple ID email (up to 100 internal testers,
   no App Review needed; builds appear minutes after upload).

## Every build

```bash
cd native/ios
xcodegen generate
open AnanseKeyboard.xcodeproj
```

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID (or pick the team
   under Signing & Capabilities for **both** targets after generating).
2. Bump the build number (`CURRENT_PROJECT_VERSION` in `project.yml`) — every
   TestFlight upload needs a build number higher than the last.
3. Select the **AnanseApp** scheme, destination **Any iOS Device (arm64)**.
4. **Product → Archive**, then in the Organizer: **Distribute App →
   TestFlight & App Store → Upload** (accept the defaults; Xcode manages
   signing).
5. When processing finishes in App Store Connect, add the build to the
   Internal Testing group. Testers get a TestFlight notification and install.

## Before inviting testers

From the repo root, confirm both native apps point at the same live API:

```bash
scripts/check-native-api-url.sh --live
```

This verifies the iPhone and Android configs share one API base URL
(`https://anansekeyboard.com/api`) and that its `/healthz` responds. Then run
the cross-device checklist in `native/RELEASE_GATE.md`.
