<p align="center">
  <img src="docs/media/icon.png" width="128" height="128" alt="Unhoard app icon: two glass cards and a sparkle on a violet glow">
</p>

<h1 align="center">Unhoard</h1>

<p align="center">
  <b>Your camera roll, minus the junk.</b><br>
  Swipe away screenshots, blurry shots, near-identical re-takes and forgotten videos.<br>
  Free, scanned on your iPhone, open source.
</p>

<p align="center">
  <!-- TODO: when the app is live, link this badge to its App Store page and change "coming soon" to "download". -->
  <img src="https://img.shields.io/badge/App_Store-coming_soon-8b5cf6?logo=appstore&logoColor=white" alt="App Store: coming soon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-a855f7" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-c026d3?logo=apple&logoColor=white" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-db2777?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <img src="https://img.shields.io/badge/scan-on--device-7c3aed" alt="Scans on the device">
  <img src="https://img.shields.io/badge/tracking-none-16a34a" alt="No tracking">
</p>

<p align="center">
  <a href="https://kleash.github.io/unhoard/">Website</a> ·
  <a href="https://kleash.github.io/unhoard/support.html">Support</a> ·
  <a href="https://kleash.github.io/unhoard/privacy.html">Privacy</a> ·
  <a href="#for-developers">Build it yourself</a>
</p>

<p align="center">
  <img src="docs/media/home.jpg" width="23%" alt="Home: every category with its count and size">
  <img src="docs/media/swipe.jpg" width="23%" alt="Swipe: left to delete, right to keep">
  <img src="docs/media/screenshots.jpg" width="23%" alt="Screenshots: select them all and clear them in one go">
  <img src="docs/media/compare.jpg" width="23%" alt="Compare: two similar shots side by side">
</p>

<!-- TODO: uncomment once docs/media/demo.gif exists.
<p align="center"><img src="docs/media/demo.gif" width="300" alt="Unhoard demo: scanning, swiping and deleting"></p>
-->

<p align="center">
  <img src="docs/media/zero.svg" width="100%" alt="0 ads, 0 subscriptions, 0 trackers, 100% open source">
</p>

## 🔎 What it finds

| | Category | What's in it |
| :-: | --- | --- |
| 📸 | **Screenshots & Recordings** | Every screenshot and screen recording, oldest first |
| 👯 | **Similar Shots** | Near-identical re-takes taken within 2 minutes, grouped, with the **Best** one marked |
| 🌫️ | **Blurry** | Photos with nothing in focus (night shots are left out) |
| 🧾 | **Utility Shots** | Receipts, labels, whiteboards: photos of things, not moments |
| 🎬 | **Large Videos** | Everything over 50 MB, biggest first |
| 🫣 | **Accidental Clips** | Pocket shots and covered-lens clips under 3 seconds |
| ✨ | **Short Moments** | Other clips under 3 seconds. **Make Still** keeps the sharpest frame as a photo |
| 💬 | **Saved from Apps** | Media that chat and social apps saved to your library, labelled with the app |
| 🔐 | **Sensitive** | Passports, IDs, cards, passwords, Wi-Fi labels. Hide them in the locked Hidden album |

Every category shows its count and size. Exact duplicates? Apple Photos already has a Duplicates album for those.

## 💜 Why it's different

- **Free, for real.** No subscription, no ads, no in-app purchases, no account.
- **Scanned on your iPhone.** Analysis runs on local thumbnails with Apple's Vision framework. No server.
- **Open source.** MIT-licensed. Every threshold is in [the table below](#how-the-categories-are-chosen), with how
  well it works.
- **Memory guard.** Favourites, edited photos and photos in your own albums are never selected for you.
- **Scans that pick up where they left off.** Stop halfway, and it carries on from there. Later scans only read
  what changed, and a scan keeps going in the background as long as iOS allows.
- **Swipe or select.** A card stack (left to delete, right to keep, with Undo), or a grid where you drag to select a
  range.
- **Nothing goes without you.** Everything waits in one delete tray, and iOS asks you to confirm once.

## ⚡ How it works in 30 seconds

1. Open Unhoard and allow access to Photos. Categories fill in while it scans.
2. Pick a category. Swipe left to delete, right to keep, or tap and drag in the grid.
3. Tap the floating **Delete** button, check the tray, and confirm.
4. To get the space back right away, empty **Recently Deleted** in Photos (see the FAQ).

## 🔒 Privacy

Unhoard has no accounts, analytics, ads or tracking, and the developer collects nothing. The only network request it
makes itself is optional: a **second opinion from Claude** on borderline photos, with your own Anthropic API key,
after a consent sheet shows the exact small previews that will be sent (512 px at most, no location, dates or camera
details). Sensitive and hidden photos are never sent. With Apple Intelligence (iOS 27), the second opinion can run on
the iPhone instead.

Don't take our word for it: turn on
[App Privacy Report](https://support.apple.com/en-us/102188) (Settings › Privacy & Security › App Privacy Report)
and see for yourself. Full details in the [privacy policy](https://kleash.github.io/unhoard/privacy.html).

## ❓ FAQ

<details>
<summary><b>Does it upload my photos?</b></summary>

No. Scanning runs on your iPhone. The only time anything leaves it is if you ask Claude for a second opinion, which
is off until you add your own API key, and you see exactly which small previews go before you confirm.
</details>

<details>
<summary><b>I deleted gigabytes. Why is my storage still full?</b></summary>

Deleted items go to **Recently Deleted** and stay there for 30 days, so you can change your mind. The space comes
back when it's emptied: Photos › Utilities › Recently Deleted › Select › Delete All. Apps aren't allowed to empty it
for you.
</details>

<details>
<summary><b>Will it delete my favourites?</b></summary>

Not unless you pick them yourself. Favourites, edited photos and photos in your albums are never selected for you,
and nothing is deleted until you confirm. If you use an iCloud Shared Library, deleting a shared item removes it for
everyone in it.
</details>

<details>
<summary><b>Is it really free?</b></summary>

Yes: no ads, no subscription, no in-app purchases. The optional Claude second opinion uses your own Anthropic key,
so Anthropic bills you for that if you use it.
</details>

<details>
<summary><b>How accurate is it?</b></summary>

Screenshots, recordings and large videos come straight from what iOS records, so those lists are exact. The rest is
image analysis, tuned cautiously: Blurry finds few photos and isn't perfect, so only Similar Shots ever selects anything
for you, and it keeps the best of each group. The honest numbers are [below](#how-the-categories-are-chosen).
</details>

<br>

---

## For developers

Unhoard is an iPhone app that helps you clean up your photo library. It finds screenshots and screen recordings,
similar shots, blurry photos, utility shots (receipts, labels, whiteboards), sensitive photos (passports, cards,
passwords), large videos, accidental clips, short moments and media saved from chat and social apps. You review them in a grid or one at a
time with swipes, collect what should go in a delete tray, and delete it all in one step.

### Features

- **Categories**, each with a count and size:
  - Screenshots & Recordings (oldest first): `PHAssetMediaSubtype.photoScreenshot`, plus screen recordings. A
    recording is matched by `.videoScreenRecording` (iOS 13+) or by membership of the Screen Recordings smart album
    (`.smartAlbumScreenRecordings`, iOS 14+), because the subtype isn't reliably set on every recording.
  - Large Videos: videos over 50 MB, biggest first.
  - Accidental Clips: clips under 3 seconds where all 3 sampled frames are very dark or nearly one flat colour (lens
    covered, phone in a pocket). These are checked on a 64 px rendition, which may come from iCloud.
  - Short Moments: the other clips under 3 seconds. **Make Still** saves the sharpest of 5 full-resolution frames as a
    photo, with the clip's date and location, and puts the clip in the tray.
  - Similar Shots: photos taken within 2 minutes of each other that look alike, in groups. Each group's best pick is
    marked **Best**; the rest are put in the tray when you open the category (the only category that does this, and
    the memory guard still applies). Exact duplicates and bursts are left to Apple Photos.
  - Blurry (blurriest first): photos with nothing in focus. Dark and night shots are left out.
  - Utility Shots (lowest score first): photos Apple's aesthetics model calls utility or scores low, other than
    screenshots and sensitive photos. Needs a real iPhone (see below). **Second Opinion** can relabel them.
  - Sensitive (newest first): passports, IDs, licences, cards, visas and passes, prescriptions, medical cards,
    signatures, Wi-Fi labels. **Hide** moves one to the Face ID-locked Hidden album; you can also tap it into the tray.
    Sensitive items are never pre-selected, never picked by Select All or a drag, and never sent to any AI.
  - Saved from Apps (biggest first), labelled with the app: media in albums that chat and social apps create
    (WhatsApp, WhatsApp Business, Telegram, Signal, Messenger, Viber, WeChat, LINE, Instagram, Snapchat, Facebook,
    TikTok, X, Twitter, Pinterest, Threads; whole-title match), or with a chat app's own file-name pattern (see
    `AssetRecord.chatApp(fileName:)`). Bare UUID file names aren't used, because other apps save files with them too.
- **Memory guard**: favourites, edited items and items in your own albums are never selected for you, and they carry a
  badge. Select All skips them, and so does a drag across the grid. You can still tap them one by one.
- **Review**: a Photos-style grid where you tap to select and long-press to preview (videos play). A sideways drag
  selects a range, and a vertical drag scrolls. **Swipe** mode is a stack of cards: left to delete, right to keep,
  and Undo. **Compare** (Similar Shots) shows a group two at a time with zoom and pan in step; tap a shot to keep it
  instead of the best pick (the old keeper goes to the tray, unless the memory guard protects it).
- **Delete tray**: the floating Delete button shows the count and size and opens the tray. The tray is saved across
  launches. Tap an item to keep it. Delete runs one PhotoKit request, so iOS asks for confirmation once. Deleted items
  stay in Recently Deleted for 30 days, and the space comes back only when Recently Deleted is emptied (iPhone does it
  after 30 days; the summary tells you how to do it now, since apps can't). Afterwards a summary shows what was cleared, and **History** (on the home screen)
  charts what you've cleared over time, kept in a small file on the iPhone. If your library is an iCloud Shared Library, deleting removes items for
  everyone in it.
- **AI second opinion** (Utility Shots): labels each borderline photo a *memory*, *utility* shot or *accident*, with a
  one-line reason, and sorts memories last. It never deletes or selects anything. On iOS 27 with Apple Intelligence
  it runs on the iPhone (Foundation Models, free and private). Or, opt in with your own Anthropic API key (Keychain,
  Second Opinion settings): a consent sheet first shows the exact previews that will be sent, at most 100 per ask,
  sent 20 per request as ≤512 px JPEGs redrawn from pixels (no location, dates or camera data). Model
  `claude-opus-5-5` at low effort, structured output, server-side fallback on refusals.
- **Scanning**: the first scan reads every item's metadata, never the originals; only the few short clips are
  downloaded to check them. Photo analysis then runs on local thumbnails only (512 px, 1024 px for reading text; no
  network), and resumes like the rest of the scan. The scan is saved every few seconds, so a scan that was stopped resumes where it left off.
  Later scans read only what changed (persistent change tokens, falling back to a full pass). Progress shows a
  percentage and an estimate of the time left, and the categories fill in while the scan runs.
- **Background**: when you leave the app, the scan keeps going for the time iOS gives it (a background-task
  assertion). On iOS 26 and later, a first or unfinished full scan also runs as a continued-processing task, with
  iOS's own progress UI. While a scan is unfinished, an overnight processing task (only when the phone is charging)
  finishes it.

### How the categories are chosen

All on local thumbnails with Apple's Vision framework (iOS 18 API), in `PhotoAnalysis.swift`.

| Category | Uses | Threshold and why |
| --- | --- | --- |
| Utility Shots | `CalculateImageAestheticsScoresRequest`: `isUtility`, `overallScore` (-1…1) | `isUtility` or score < 0. Apple's private Photos score isn't available, so this is Vision's own scale: on sample pictures real scenes scored 0.45–0.9, a receipt 0.1 (utility), flat graphics -0.2 to -0.4; 0 is the midpoint. Not yet calibrated on a real library; on one, about a fifth of low scorers were real memories (night, festival, blurry family shots), which is why nothing is pre-selected and the second opinion exists. |
| Sensitive | Candidates only (utility, low score, screenshot, or `DetectDocumentSegmentationRequest` finds a document): `RecognizeTextRequest` on a 1024 px thumbnail, `DetectBarcodesRequest`, `DetectFaceRectanglesRequest` | Passport/ID MRZ lines (25+ of `A–Z0–9<` with `<<`), card numbers passing Luhn, IBANs passing mod-97, keywords (passport, licence/license, visa, pass, date of birth, DOB, FIN, NRIC, prescription, Rx, SSID, WPA, password, insurance, medical, signature, …), Wi-Fi QR codes, boarding-pass barcodes, PDF417/Aztec codes, or an ID-shaped document (confident outline, long/short side 1.3–1.7, under 95% of the frame, 3+ text lines on it) with exactly one small face on it. Tuned for recall: a false alarm only keeps an item out of bulk selection. |
| Similar Shots | `GenerateImageFeaturePrintRequest` on 512 px thumbnails, each photo against the previous one in time (O(n)) | Within 2 minutes and feature-print distance < 0.15. On a real 6,900-photo library, pairs under 0.10 were nearly all re-takes of one shot, 0.10–0.15 mostly, 0.15–0.20 about half, above 0.20 mostly a different pose or framing at the same spot. |
| Best pick | Favourite, then `DetectFaceCaptureQualityRequest` (when both have faces, 0.05 apart), then sharpness (15% apart), then aesthetics score | |
| Blurry | Variance of the Laplacian on a 512 px grey copy, in each face box or else each tile of a 3×3 grid, taking the sharpest (so bokeh with a sharp subject passes); `DetectLensSmudgeRequest` (iOS 26+) as a second vote | Blurry below 40 (sharp photos measure in the hundreds), or below 80 with smudge confidence ≥ 0.7. Mean brightness under 0.15 (night shots) is never called blurry, since noise fakes sharpness. |

**Precision, honestly:** these thresholds were set on synthetic and sample pictures, not on a real camera roll. Apple's
own sharpness score failed on a real library, and a competitor found only about one blurry photo per 2,000, so expect
Blurry to be small and imperfect; nothing in it is pre-selected. Similar Shots is the only category that pre-selects,
and it keeps each group's best.

**Simulator:** only text recognition and document detection run there. Aesthetics, feature prints, faces, barcodes and
lens smudge fail, so Utility Shots shows "Needs an iPhone" and Similar Shots stays empty. Debug builds launched with
`-UnhoardSimulatorStandIns` (the UI walkthrough does) use stand-ins for aesthetics and feature prints.

### Privacy

Everything happens on your iPhone. No accounts, no analytics. The only network request Unhoard makes itself is the
opt-in Claude second opinion, after the consent sheet, with your own key. Photos may download originals from iCloud
for previews and short-clip checks; photo analysis never downloads anything. Unhoard asks for full Photos access to read and delete, and
for permission to add the stills it makes.

### Requirements

- Xcode 27.2 (iOS SDK 27), deploying to iOS 18 or later, iPhone only
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the `.xcodeproj` and `Unhoard/Info.plist` are generated and not committed)

### Build, run and test

```sh
xcodegen generate
open Unhoard.xcodeproj
```

Run the `Unhoard` scheme on a simulator or a device. For a device, pick your team under Signing & Capabilities.

```sh
xcodebuild test -project Unhoard.xcodeproj -scheme Unhoard   -destination 'id=<simulator udid>'   # unit tests
xcodebuild test -project Unhoard.xcodeproj -scheme UnhoardUI -destination 'id=<simulator udid>'   # walkthrough, screenshots in /tmp/unhoard-shots/design
```

Add some media to the simulator first with `xcrun simctl addmedia <udid> <files…>`: a few screenshots, clips and
videos, a photo of a passport-like page (for Sensitive), and two or three near-identical photos taken seconds apart (for
Similar Shots). The walkthrough never confirms a delete, never hides anything and never sends anything to Claude (it
saves a fake key to show the consent sheet, then removes it).

Some tests read back from Photos (the saved still, the stop-and-resume scan), and they need full Photos access on the
simulator, which `simctl` alone doesn't grant fully. Install the app once (run the tests once), then:

```sh
xcrun simctl privacy <udid> grant photos com.kleash.unhoard
xcrun simctl privacy <udid> grant photos-add com.kleash.unhoard
xcrun simctl shutdown <udid>
sqlite3 ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/TCC/TCC.db \
  "update access set auth_version=2 where service='kTCCServicePhotos' and client='com.kleash.unhoard'"
xcrun simctl boot <udid>
```

### App Store notes

- **File sizes use an undocumented PhotoKit key.** Sizes are read with `PHAssetResource.value(forKey: "fileSize")`.
  This isn't public API, so App Review may flag it or a future iOS may drop it. Unhoard checks that the key exists
  first, and when it can't read a size it estimates one from pixel count (photos) or duration × resolution (videos).
  See `AssetRecord.fileSize`.
- Background scanning only works on a device. The simulator doesn't run continued-processing or processing tasks.

### Release

```sh
DEVELOPMENT_TEAM=<team id> scripts/release-ios.sh            # archive, check, export build/ios/Unhoard.ipa
DEVELOPMENT_TEAM=<team id> scripts/release-ios.sh --upload   # and upload for TestFlight
```

The app icon (two glass cards and a sparkle on a violet-to-magenta glow) is drawn by `swift scripts/make-icon.swift Unhoard/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

### License

MIT, see [LICENSE](LICENSE).
