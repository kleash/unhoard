# Unhoard 1.0.0 – App Store Connect copy

Ready to paste. Counts are characters as App Store Connect counts them (checked with Python `len`). Bundle id
`com.kleash.unhoard`, version 1.0.0, iPhone only, iOS 18 or later.

## Name (29/30)

```text
Unhoard: Clean Up Your Photos
```

The user's pick (2026-11-12) over the research's "Unhoard: Screenshot Cleaner": the app is more than a screenshot cleaner.

## Subtitle (28/30)

```text
Screenshots, Blurry & Videos
```

In App Store Connect (en-US), with these keywords (100/100, none repeating a name or subtitle word):

```text
cleaner,delete,similar,swipe,storage,space,full,free,large,screen,recording,camera,roll,gallery,mass
```

The sets below were written for the earlier name; English (UK) falls back to the US listing for now.

## Keywords

Name and subtitle words (never repeat them in keywords): Unhoard, Screenshot, Cleaner, Swipe, Photos, Blurry,
Similar. Apple indexes the name, subtitle and keywords of a localization together, so repeats waste characters. The
two sets below share no word with each other or with the name and subtitle, and have no spaces.

### English (US) (97/100)

```text
storage,delete,duplicate,free,up,space,video,whatsapp,telegram,iphone,camera,roll,private,gallery
```

None of the starting words is in the new name or subtitle, so nothing had to be dropped.

### English (UK) (95/100)

```text
declutter,recording,receipt,clips,large,memory,organise,tidy,bulk,remover,junk,album,chat,saved
```

English (UK) is the default language in storefronts such as India, Indonesia and Turkey, so this set adds new search
words there. It uses the UK spelling `organise`.

### Review risk, decide before submitting

Guideline 2.3.7 asks you not to pack metadata with "trademarked terms, popular app names, pricing information". In the
US set, `whatsapp`, `telegram` and `iphone` are trademarks, `free` can read as pricing, and `duplicate` may set an
expectation the app doesn't meet (exact duplicates are left to Photos). A safer US set that still shares nothing with
the UK set:

```text
storage,delete,free,up,space,video,camera,roll,private,gallery,phone,pictures,accidental,screen
```

(95/100; it keeps `free`, which reads as "free up space" here; drop it if you want zero risk.) The UK set has no
trademarks or price words.

## Promotional text (153/170)

Leads with privacy (changed 2026-11-13 on the live listing; promotional text needs no review).

```text
Private by design: every scan runs on your iPhone. No account, no tracking, no ads. Clear old screenshots, blurry and similar shots and big videos, free.
```

## Description (3904/4000)

US spelling. For English (UK), paste the same text with favorites → favourites, color → colour, labeled → labelled
(UK version: 3909/4000).

```text
Got thousands of screenshots? Unhoard finds every screenshot and screen recording on your iPhone, oldest first, with how much space they take. Select them all or swipe through them one by one, then delete them in one step.

Then keep going: similar shots, blurry photos, big videos, accidental clips and media saved from chat apps, all collected in one delete tray.

Everything is scanned on your iPhone. No account, no ads, no subscription, no tracking. Unhoard is open source.

SCREENSHOTS FIRST
• Screenshots and screen recordings in one place, oldest first, with their count and size
• Select All skips favorites, edited screenshots and ones in your own albums, so the ones you kept on purpose stay
• Or swipe: left to delete, right to keep, with Undo

ALSO FINDS
• Similar shots: photos taken within two minutes of each other that look alike, grouped, with the best one marked
• Blurry photos with nothing in focus (dark and night shots are left out)
• Utility shots: receipts, labels, whiteboards and other photos of things rather than moments
• Large videos over 50 MB, biggest first
• Accidental clips: very short clips that are dark or one flat color, like a covered lens or a pocket
• Short moments: other clips under 3 seconds. Make Still saves the sharpest frame as a photo, with the clip's date and location
• Saved from apps: media that chat and social apps saved to your library, labeled with the app
• Sensitive photos: passports, IDs, cards, passwords and Wi-Fi labels. Move them to the locked Hidden album, or delete them one by one

HOW YOU CLEAN
• Grid: tap to select, drag sideways to select a range, long-press to preview
• Compare: look at similar shots two at a time, zooming both together, and pick the one to keep
• Delete tray: everything you pick waits in one tray, saved between launches, and goes in one step
• History: see how much you've cleared over time

YOUR MEMORIES COME FIRST
• Favorites, edited photos and photos in your own albums are never selected for you
• Only Similar Shots selects anything for you, and it always keeps the best of each group
• Sensitive photos are never selected in bulk
• Deleted items go to Recently Deleted in Photos and stay there for 30 days, so you can change your mind. The space comes back when Recently Deleted is emptied; Unhoard shows you how to do that in Photos
• If you use an iCloud Shared Library, deleting an item removes it for everyone in that library

PRIVATE BY DESIGN
Unhoard looks at small thumbnails of your photos on your iPhone, with Apple's Vision framework. The developer collects no data, and Unhoard has no server.

AN OPTIONAL SECOND OPINION
Not sure whether a borderline photo is a memory or clutter? Ask for a second opinion: each photo is labeled a memory, a utility shot or an accident, with a one-line reason. On iOS 27 with Apple Intelligence it runs on your iPhone. Or use Claude with your own Anthropic API key: a consent sheet first shows the exact small previews that will be sent (512 pixels at most, with no location, dates or camera details), and sensitive and hidden photos are never sent. The second opinion only labels photos; it never deletes or selects anything. You don't need it: Unhoard finds and cleans everything without it.

SCANS THAT PICK UP WHERE THEY LEFT OFF
The first scan reads your library's details, not your originals. It's saved as it goes, so a stopped scan resumes, and later scans only read what changed. Leave the app and the scan keeps going for as long as iOS allows; an unfinished scan can also finish overnight while your iPhone is charging. Categories fill in while it runs, with a percentage and the time left.

Looking for exact duplicates? Use the Duplicates album in Apple Photos; Unhoard handles the rest.

Requires full access to your photo library, to find items and to delete the ones you choose.

Open source under the MIT license: github.com/kleash/unhoard
```

## What's New in This Version

1.0.1:

```text
- Swipe across Similar Shots to select them, even across groups
- Video thumbnails show each video's size
- Rate Unhoard from History or Settings
- Fixed: a kept "Best" shot no longer lingers after the rest of its group is deleted
- Fixed: swipes now work on the first screen of Similar Shots
```

1.0.0 (226/4000):

```text
First release. Clear screenshots and screen recordings in one go, then similar shots, blurry photos, utility shots, large videos, short clips and media saved from chat apps, with a swipe or in a grid. Scans run on your iPhone.
```

App Store Connect may not show this field for a first version; if it doesn't, keep it for the release notes on GitHub.

## URLs

- Support URL: https://kleash.github.io/unhoard/support.html
- Marketing URL (optional): https://kleash.github.io/unhoard/
- Privacy Policy URL: https://kleash.github.io/unhoard/privacy.html

## Category

- Primary: **Utilities** (where storage cleaners are browsed and charted).
- Secondary: **Photo & Video**.

Swapping them is reasonable too; Photo & Video is a busier chart full of editors.

## Age rating

Answer "None" / "No" to every content question: no violence, sexual content, profanity, gambling, horror, drugs,
medical or wellness content; no unrestricted web access; no user-generated content shared with others; no messaging
or chat; no ads; no in-app purchases. Expected result: **4+**.

If the questionnaire asks about AI or generated content: the optional second opinion returns only a fixed label
(memory / utility / accident) and a one-line reason about the user's own photo. It isn't a chat, and nothing it
returns is shown to other people.

Export compliance: `ITSAppUsesNonExemptEncryption` is already `NO` (HTTPS only, through Apple's URLSession).

## App Privacy questionnaire

> **DECISION NEEDED (you):** does the optional Claude feature count as "collecting" Photos?

**Recommendation: "No, we do not collect data from this app" (label: Data Not Collected).**

Reasoning:

- Apple defines "collect" as transmitting data off the device in a way that lets **you and/or your third-party
  partners** access it for longer than needed to service the request in real time.
- The developer has no server and never receives anything. Analytics, ads, crash reporting and third-party SDKs:
  none. `Unhoard/PrivacyInfo.xcprivacy` already declares no collected data and no tracking.
- The Claude request goes from the device straight to `api.anthropic.com` under the **user's own** API key and
  Anthropic account, on the user's own agreement with Anthropic, only after the user confirms a consent sheet showing
  the exact previews. The developer has no contract or data relationship with Anthropic for this traffic, so
  Anthropic acts as the user's provider, not the developer's partner (like a mail app sending what the user tells it
  to, to the user's own mail server).

Why it's a judgement call: Anthropic does keep API inputs for a while under its own policy, and Apple's "optional
disclosure" exemption (infrequent, optional, user-initiated, clearly disclosed each time) also requires the user's
name or account name to be shown on the submission form, which the consent sheet doesn't do. A strict reviewer could
read Anthropic as a "third-party partner". Check the current wording at
https://developer.apple.com/app-store/app-privacy-details/ before you choose.

**Conservative alternative:** answer "Yes", declare one type:

- Data type: **Photos or Videos**
- Purpose: **App Functionality** only
- Linked to the user's identity: **No** (the developer has no identity to link to)
- Used for tracking: **No**

Label result: "Data Not Linked to You: Photos or Videos". It costs the clean "Data Not Collected" badge, which
matters for this app's pitch. If you pick it, add a matching `NSPrivacyCollectedDataTypes` entry
(`NSPrivacyCollectedDataTypePhotosorVideos`, not linked, no tracking, purpose App Functionality) to
`Unhoard/PrivacyInfo.xcprivacy` so the manifest and label agree, and change the privacy policy's "the developer
collects no data" line to say a third party receives previews when the user asks.

Either way, guideline 5.1.2(i) requires telling users when personal data goes to a third-party AI and getting their
explicit permission first; the consent sheet does that, and the privacy policy names Anthropic.

## App Review notes (2055/4000)

```text
Unhoard is a free photo-library cleaner. No login, no in-app purchases, no account. Everything runs on the device; nothing is deleted without the system confirmation dialog, and deleted items go to Recently Deleted (recoverable for 30 days).

TESTING WITHOUT A BIG LIBRARY
Please test on a physical iPhone: Utility Shots and Similar Shots use Vision features that don't run in the simulator. Before opening the app, on the device:
1. Take 2–3 screenshots (Screenshots & Recordings).
2. Take 3 photos of the same object a few seconds apart (Similar Shots, best pick marked).
3. Photograph a receipt or a label (Utility Shots).
4. Record a 1–2 second video with the lens covered (Accidental Clips), and one normal 1–2 second video (Short Moments; open it and tap Make Still).
Then open Unhoard, allow Full Access to Photos, and the scan finishes in seconds. Open any category, tap or swipe items into the delete tray, tap Delete and confirm the system dialog.

OPTIONAL SECOND OPINION
This feature is optional, and the rest of the app works fully without it. It can be skipped.
- On iOS 27 with Apple Intelligence it runs on the device ("On This iPhone").
- "Ask Claude" needs the user's own Anthropic API key (home screen > Second Opinion Settings). We don't run a server or provide a shared key; to try it, please use your own key from console.anthropic.com. Before anything is sent, a consent sheet shows the exact previews (at most 512 px JPEGs redrawn from pixels, no location, dates or camera data). Sensitive and hidden photos are never sent. The only network request the app makes is to api.anthropic.com, after that confirmation.

FILE SIZES
To show exact sizes, Unhoard reads PHAssetResource's "fileSize" key with value(forKey:). The app checks that the key exists first; if it's missing or unreadable, it falls back to an estimate from pixel count (photos) or duration × resolution (videos).

BACKGROUND
The background "processing" mode and a continued-processing task (iOS 26+) are used only to finish a photo-library scan that the user started.
```

## Screenshot plan

6.9-inch iPhone (1320 × 2868); App Store Connect scales them for smaller iPhones. Use a demo library, not personal
photos. The UI walkthrough (`-scheme UnhoardUI`) and the `-Unhoard*` debug launch arguments (light/dark, onboarding,
celebration demo) produce most of these; Similar Shots and Utility Shots need a real iPhone or the simulator
stand-ins.

1. **Screenshots & Recordings: count, total size and Select All.** Caption: "Private cleanup, right on your iPhone" (from 1.0.1; image docs/media/store-next-01.png; 1.0.0 had "Clear old screenshots in one go")
2. **Swipe mode on a screenshot, card mid-swipe with the DELETE stamp.** Caption: "Swipe left to delete, right to keep"
3. **Compare in Similar Shots, Best badge visible.** Caption: "Keep the best of every similar shot"
4. **Home: all categories with counts and sizes.** Caption: "Blurry shots, big videos and more"
5. **Home trust row or the Claude consent sheet.** Caption used: "Review everything before it's deleted" (the shots are made by `UnhoardUITests/StoreScreenshotsUITests` on a simulator loaded with stock media only)

Avoid captions like "Everything stays on your iPhone" without the Claude caveat, and any "free" price wording on the
first two shots.
