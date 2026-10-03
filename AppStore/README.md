# Publishing Notcher on the Mac App Store

Everything in the app is ready for the Mac App Store:
- It runs in the App Sandbox and ships a privacy manifest.
- A sandboxed build is tested in CI.
- Screenshots and listing text are in this folder.

What's left needs your Apple Developer account. Do it once, in this order. After that, each new version is one upload.

| Step | Where | Time |
| --- | --- | --- |
| [1. Register the App ID](#1-register-the-app-id) | developer.apple.com | 2 min |
| [2. Make the two certificates](#2-make-the-two-certificates) | Keychain Access + developer.apple.com | 10 min |
| [3. Make the provisioning profile](#3-make-the-provisioning-profile) | developer.apple.com | 2 min |
| [4. Create the app in App Store Connect](#4-create-the-app-in-app-store-connect) | appstoreconnect.apple.com | 15 min |
| [5. Build and upload](#5-build-and-upload) | your Mac, or GitHub Actions | 10 min |
| [6. Test with TestFlight, then submit](#6-test-with-testflight-then-submit-for-review) | App Store Connect | review takes 1–3 days |

You need a paid [Apple Developer Program](https://developer.apple.com/programs/) membership and Xcode 26 or later (App Store Connect only accepts apps built with the macOS 26 SDK or newer).

## 1. Register the App ID

[Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → **+** → **App IDs** → **App**.

- **Description:** Notcher
- **Bundle ID:** Explicit, `app.notcher.Notcher`. If that's taken, use your own, such as `com.yourname.Notcher`. The build scripts read the bundle ID from your provisioning profile, so nothing in the code needs changing.
- **Capabilities:** leave them all off.

## 2. Make the two certificates

The App Store needs two certificates, which are different from the Developer ID certificate used for the DMG:
- **Apple Distribution** signs the app.
- **Mac Installer Distribution** signs the installer package.

For each one:

1. In **Keychain Access**, choose **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**. Enter your email, choose **Saved to disk** and save the `.certSigningRequest` file.
2. Go to [Certificates](https://developer.apple.com/account/resources/certificates/list) → **+** and pick the certificate:
   - **Apple Distribution**
   - **Mac Installer Distribution**
3. Upload the request, download the certificate and double-click it to add it to your keychain.

Check that both are there with their private keys:

```sh
security find-identity -v                 # lists "Apple Distribution: …" and "3rd Party Mac Developer Installer: …"
```

(Xcode can make both for you too: **Settings → Accounts → Manage Certificates → +**.)

## 3. Make the provisioning profile

[Profiles](https://developer.apple.com/account/resources/profiles/list) → **+** → **Distribution → Mac App Store Connect** → choose the Notcher App ID → choose your Apple Distribution certificate → name it `Notcher App Store` → **Generate** → download it.

## 4. Create the app in App Store Connect

Go to [App Store Connect → Apps](https://appstoreconnect.apple.com/apps), then **+ → New App**.

| Field | Value |
| --- | --- |
| Platform | macOS |
| Name | `Notcher` (names are unique across the store; if it's taken, try `Notcher: Notch Arcade`) |
| Primary language | English (U.S.) |
| Bundle ID | the one from step 1 |
| SKU | `notcher` |

Then fill in the listing. Everything you need is in this folder:

| App Store Connect field | Copy from |
| --- | --- |
| Subtitle | [metadata/en-US/subtitle.txt](metadata/en-US/subtitle.txt) |
| Promotional text | [metadata/en-US/promotional_text.txt](metadata/en-US/promotional_text.txt) |
| Description | [metadata/en-US/description.txt](metadata/en-US/description.txt) |
| Keywords | [metadata/en-US/keywords.txt](metadata/en-US/keywords.txt) |
| Support URL | [metadata/en-US/support_url.txt](metadata/en-US/support_url.txt) |
| Marketing URL | [metadata/en-US/marketing_url.txt](metadata/en-US/marketing_url.txt) |
| Privacy policy URL (App Privacy) | [metadata/en-US/privacy_url.txt](metadata/en-US/privacy_url.txt), which points at [docs/privacy.md](../docs/privacy.md) |
| Screenshots (macOS) | the five images in [Screenshots/](Screenshots), in order |
| App Review notes | [metadata/review_information/notes.txt](metadata/review_information/notes.txt) |

And the rest:

- **Category:** Games, subcategories **Arcade** and **Puzzle**.
- **Age rating:** Notcher has no web access, chat or user-generated content. The only judgment call is the arcade shooters. Answering **None** for violence gives 4+. **Infrequent/Mild Cartoon or Fantasy Violence** is the cautious choice and gives 9+.
- **App Privacy:** **Data Not Collected**.
- **Pricing and availability:** your choice.
- **Copyright:** `2026 Your Name`.
- **App Review contact:** your details. Sign-in required: **No**.

The metadata folder uses the same layout as [fastlane deliver](https://docs.fastlane.tools/actions/deliver/), so `fastlane deliver` can upload it if you use fastlane.

## 5. Build and upload

### On your Mac

```sh
APPSTORE_PROFILE=~/Downloads/Notcher_App_Store.provisionprofile make appstore
```

This builds a universal, sandboxed `build/Notcher.app` and signs it with your Apple Distribution certificate. It embeds the profile and wraps the app in `build/Notcher.pkg`, signed with your installer certificate.

To upload it, use one of these:
- **Transporter** ([free on the Mac App Store](https://apps.apple.com/app/transporter/id1450874784)): sign in, drag in `build/Notcher.pkg`, click **Deliver**.
- **The command line:** create an API key ([Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api), role **App Manager**). Put the downloaded `AuthKey_<KEY_ID>.p8` in `~/.appstoreconnect/private_keys/`, then:

  ```sh
  APPSTORE_API_KEY_ID=<KEY_ID> APPSTORE_API_ISSUER_ID=<ISSUER_ID> \
  APPSTORE_PROFILE=~/Downloads/Notcher_App_Store.provisionprofile \
  ./Scripts/build-appstore.sh --upload
  ```

Every upload needs a higher build number. It's the commit count, so commit before building again. You can also set `NOTCHER_BUILD`. The version shown in the store comes from the [VERSION](../VERSION) file.

### From GitHub Actions

The [App Store workflow](../.github/workflows/appstore.yml) does the same thing in the cloud.

1. Export both certificates as one file. In Keychain Access → **My Certificates**, select both **Apple Distribution: …** and **3rd Party Mac Developer Installer: …** → right-click → **Export 2 items…** → save as `appstore.p12` with a password.
2. Create the API key as above.
3. Add the secrets. Each command prompts for the value, or reads it from a file, so nothing ends up in your shell history:

   ```sh
   base64 -i appstore.p12 | gh secret set APPSTORE_CERTIFICATES -R jeothecreator/Notcher
   gh secret set APPSTORE_CERTIFICATES_PASSWORD -R jeothecreator/Notcher
   base64 -i ~/Downloads/Notcher_App_Store.provisionprofile | gh secret set APPSTORE_PROFILE -R jeothecreator/Notcher
   gh secret set APPSTORE_API_KEY_ID -R jeothecreator/Notcher
   gh secret set APPSTORE_API_ISSUER_ID -R jeothecreator/Notcher
   gh secret set APPSTORE_API_KEY -R jeothecreator/Notcher < ~/Downloads/AuthKey_<KEY_ID>.p8
   ```

   You can also add them in the repository's **Settings → Secrets and variables → Actions**.
4. Run it: **Actions → App Store → Run workflow**. Or push a commit with `[appstore]` in its message.

Without the secrets, the workflow still runs Notcher in the sandbox to check that it works. It also renders fresh screenshots (the run's **Notcher-AppStore-screenshots** artifact).

## 6. Test with TestFlight, then submit for review

1. After an upload, the build shows up in App Store Connect under **TestFlight** once Apple has processed it (usually under 30 minutes). Install it with the TestFlight app on your Mac.
2. Things to check in that build:
   - The notch opens.
   - **Try the demos** works.
   - A game file dragged onto the notch starts.
   - A game controller works.
   - Your scores carried over from the DMG version.
3. On the version page, under **Build**, choose the upload, then click **Add for Review → Submit**.

## Things App Review may ask about

- **Emulators (guideline 4.7).** Apple has allowed retro console emulators since 2024, as long as they don't come with games you don't have the rights to. Notcher includes no commercial games and downloads nothing, and the review notes say so. The three demo games are original to Notcher.
- **Trademarks.** The keywords, subtitle and screenshots don't use Nintendo's trademarks. The description names NES and Game Boy only to say which files it opens, with a disclaimer.
  - Two built-in games are named after other companies' trademarks: **Pong** and **Breakout** (both Atari's). App Review rarely objects to names inside an app, but if they do, rename those two in `Sources/NotcherCore/Meta/GameCatalog.swift` (for example **Rally** and **Bricks**).
- **"Where is the app?"** It's a menu bar app with no window. The review notes explain how to open it.
- **Name taken.** If `Notcher` is already used by another app, pick another name in step 4. The name on the store doesn't have to match the app's file name.

## What's in the App Store build

The App Store build differs from the DMG build in these ways:

| | |
| --- | --- |
| Sandbox | [Resources/Notcher.entitlements](../Resources/Notcher.entitlements): App Sandbox, read access to files you choose, Bluetooth and USB for controllers. No network. |
| Privacy manifest | [Resources/PrivacyInfo.xcprivacy](../Resources/PrivacyInfo.xcprivacy): no tracking, no data collected. |
| Moving from the DMG version | [Resources/container-migration.plist](../Resources/container-migration.plist) moves your saves and ROM library into the sandbox the first time the App Store version starts. |
| Encryption | `ITSAppUsesNonExemptEncryption = NO` in Info.plist, so there's no export compliance question on each upload. |
| Updates | Through the App Store. The DMG releases on GitHub carry on separately. |

Run `make sandbox` to try the sandboxed version locally. It runs under its own bundle ID, so it doesn't touch your normal data.
