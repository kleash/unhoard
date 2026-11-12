# Unhoard – outreach drafts

> **DRAFTS ONLY. Nothing here has been sent or posted.** Edit, fill the TODOs, and send or post them yourself.
> Never name or criticise another app; let readers compare for themselves.

Links to fill in: App Store `TODO`, site https://kleash.github.io/unhoard/, code https://github.com/kleash/unhoard.

---

## 1. Email to authors of "best free iPhone photo cleaner" roundups (DRAFT)

**Subject:** A free, open-source pick for your iPhone photo cleaner roundup

Hi [name],

I read your "[article title]" ([link]). A lot of the apps that used to be the free picks in lists like yours now ask
for a subscription before you can delete much, so I thought a genuinely free one might be useful for an update.

I made Unhoard, an iPhone photo cleaner that's free with no subscription, ads or account, and open source (MIT). It
finds screenshots and screen recordings, similar shots (keeping the best of each group), blurry photos, receipts and
other utility shots, large videos, accidental clips and media saved from chat apps. You swipe or tap items into one
delete tray and delete them in one step. Favourites and photos in your albums are never selected for you.

The scan runs on the iPhone; nothing is uploaded. (There's an optional AI second opinion that uses the reader's own
API key, and it shows exactly what it would send first.)

- App Store: TODO
- Website: https://kleash.github.io/unhoard/
- Source: https://github.com/kleash/unhoard

Happy to answer questions or send screenshots.

Thanks,
[your name]

---

## 2. Show HN (DRAFT)

**Title** (HN limit 80 characters):

```text
Show HN: Unhoard – an open-source iPhone photo cleaner that runs on the device
```

**URL:** https://github.com/kleash/unhoard

**Text:**

I cleaned up my own iCloud library (about 8,600 items) by hand with scripts, and then wanted the same thing as an
iPhone app that's free, doesn't need a subscription and doesn't upload my photos. So I built Unhoard and put it under
MIT.

It's SwiftUI and PhotoKit, with Apple's Vision framework on local thumbnails:

- Similar shots: a feature print of each photo compared with the previous one in time (O(n)), within 2 minutes and
  distance < 0.15. The best pick comes from favourites, then face capture quality, then sharpness, then aesthetics.
- Blurry: variance of the Laplacian per face box or per tile of a 3×3 grid, taking the sharpest, so bokeh with a sharp
  subject passes. Dark shots are skipped because noise fakes sharpness.
- Utility shots: Vision's aesthetics request (`isUtility` or a score below 0).
- Sensitive photos (IDs, cards, Wi-Fi labels): text recognition plus MRZ, Luhn and IBAN checks, barcodes, and an
  ID-shaped document with one small face. These are never selected in bulk.
- The scan is resumable and incremental (persistent change tokens), and keeps going in the background where iOS
  allows it (continued-processing tasks on iOS 26+).

Things I'd rather be upfront about:

- The thresholds were tuned on sample pictures and one real library, not a big set. Blurry finds few photos and isn't
  perfect, so only Similar Shots ever pre-selects anything, and it keeps each group's best.
- Exact file sizes come from PHAssetResource's undocumented `fileSize` key, checked first, with an estimate as the
  fallback.
- Exact duplicates are left to the Photos Duplicates album.
- There's an optional "second opinion" for borderline shots: on-device with Apple Intelligence on iOS 27, or Claude
  with your own API key. A consent sheet shows the exact ≤512 px previews first (no location, dates or EXIF), and
  sensitive or hidden photos are never sent. It's the only network request the app makes.

Deletes go to Recently Deleted (30 days). App Store: TODO. I'd love feedback on the detection, especially from
people with big libraries.

---

## 3. Reddit launch post, from your own account (DRAFT)

**Subreddit: r/iosapps.** It exists for sharing iOS apps and developers post there. Its rules (as I understand them;
re-read the sidebar before posting, they change): say you're the developer, use the right post flair, one post per
app, no vote begging, and answer comments. Bigger subs like r/iphone and r/apple restrict app self-promotion, so
don't cross-post there unless their current rules allow it.

**Title:**

```text
I had [6,000] screenshots on my iPhone, so I built a free, open-source cleaner with no subscription
```

**Body:**

I had [6,000] screenshots and [X GB] of photos I'd never look at again. [Fill in your real numbers.] I wanted to
clear them without paying for a subscription or uploading my library anywhere, so I built Unhoard. I'm the
developer.

What it does:

- Finds screenshots and screen recordings, similar shots (keeps the best one), blurry photos, receipts, big videos,
  accidental pocket clips and media saved from chat apps
- Swipe left to delete, right to keep, or select in a grid; everything goes in one tray you delete in one step
- Never selects your favourites, edited photos or photos in your albums for you
- Free: no ads, no subscription, no account. The scan runs on your iPhone
- Open source (MIT): https://github.com/kleash/unhoard

Honest limits: blurry detection is cautious and finds only a few, and exact duplicates are left to the Photos
Duplicates album. Deleted items go to Recently Deleted, so empty that in Photos to get the space back.

App Store: TODO. I'd love feedback, especially on what it misses.

---

## 4. Threads post, from your own account (DRAFT)

Threads allows 500 characters; this is 374, including the placeholders.

```text
I had [6,000] screenshots on my iPhone. [Fill in your real number.]

So I built Unhoard. It finds screenshots, blurry and similar shots, big videos and pocket clips, and you swipe them away: left to delete, right to keep.

Free: no subscription, no ads, no account. The scan runs on the iPhone, and the code is open source.

App Store: [TODO]
Code: github.com/kleash/unhoard
```

---

## Skipped: creator and influencer pitches

Cold pitches to creators or influencers are skipped by decision; there are none in this file. Only the roundup-author
email (section 1) is outreach to people you don't know.

---

## 5. AlternativeTo listing (DRAFT)

**Name:** Unhoard
**Platform:** iPhone · **License:** Free, Open Source (MIT)
**Links:** https://kleash.github.io/unhoard/ · https://github.com/kleash/unhoard · App Store TODO
**Tags:** photo-cleaner, storage-cleaner, privacy, open-source, no-subscription

**Description:**

Unhoard is a free, open-source iPhone app for cleaning up your photo library. It finds screenshots and screen
recordings, similar shots (with the best of each group marked), blurry photos, utility shots like receipts and
labels, large videos, accidental clips and media saved from chat and social apps, and shows how much space each
category takes. Review with swipes or a grid, collect items in one delete tray, and delete them in one step.
Favourites, edited photos and photos in your albums are never selected for you. Scanning runs on the iPhone with no
account, ads or tracking; an optional AI second opinion uses your own Anthropic API key and shows exactly what it
would send first.
