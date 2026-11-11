import Photos
import XCTest
@testable import Tidyroll

func rec(_ id: String, modified: TimeInterval = 0, video: Double? = nil, favorite: Bool = false, edited: Bool = false,
            album: Bool = false, screenshot: Bool = false, chat: Bool = false, bytes: Int64 = 1_000, accident: Bool? = nil) -> AssetRecord {
    AssetRecord(id: id, modified: Date(timeIntervalSince1970: modified), created: Date(timeIntervalSince1970: modified),
                mediaType: (video != nil ? PHAssetMediaType.video : .image).rawValue,
                subtypes: screenshot ? PHAssetMediaSubtype.photoScreenshot.rawValue : 0, duration: video ?? 0,
                width: 1920, height: 1080, isFavorite: favorite, hasAdjustments: edited, inUserAlbum: album, isBurst: false,
                isScreenRecording: false, chatApp: chat ? "WhatsApp" : nil, bytes: bytes, accident: accident)
}

final class LibraryTests: XCTestCase {
    func testIncrementalMergeAddsChangesAndDeletes() {
        let old = ["a": rec("a", modified: 1, video: 2, accident: true),
                   "b": rec("b", modified: 1, video: 2, accident: true),
                   "c": rec("c", modified: 1)]
        let fresh = [rec("a", modified: 1, video: 2), // unchanged: keeps its analysis
                     rec("b", modified: 5, video: 2), // changed: analysed again
                     rec("d", modified: 9)]          // new
        let merged = ScanCache.merge(old, fresh: fresh, deleted: ["c"], fullPass: false)
        XCTAssertEqual(Set(merged.keys), ["a", "b", "d"])
        XCTAssertEqual(merged["a"]?.accident, true)
        XCTAssertNil(merged["b"]?.accident)
        XCTAssertEqual(merged["b"]?.modified, Date(timeIntervalSince1970: 5))
    }

    func testFullPassDropsWhatItDidNotSee() {
        let old = ["a": rec("a", modified: 1, video: 1, accident: false), "gone": rec("gone")]
        let merged = ScanCache.merge(old, fresh: [rec("a", modified: 1, video: 1)], deleted: [], fullPass: true)
        XCTAssertEqual(Array(merged.keys), ["a"])
        XCTAssertEqual(merged["a"]?.accident, false)
    }

    func testPartialCheckpointKeepsUnseenRecords() {
        let old = ["a": rec("a"), "b": rec("b")]
        XCTAssertEqual(Set(ScanCache.merge(old, fresh: [rec("c")], deleted: [], fullPass: false).keys), ["a", "b", "c"])
    }

    func testCacheRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/library.plist")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = ScanCache(records: ["a": rec("a", video: 1.5, accident: true)], token: Data([1, 2, 3]))
        cache.save(to: url)
        let loaded = try XCTUnwrap(ScanCache.load(url))
        XCTAssertEqual(loaded.records, cache.records)
        XCTAssertEqual(loaded.token, cache.token)
    }

    func testCategories() {
        let records = [rec("shot", modified: 2, screenshot: true), rec("oldshot", modified: 1, screenshot: true),
                       rec("big", video: 60, bytes: 900_000_000), rec("bigger", video: 30, bytes: 2_000_000_000),
                       rec("small", video: 60, bytes: 10_000_000),
                       rec("oops", video: 1, accident: true), rec("clip", video: 2, accident: false), rec("unchecked", video: 2),
                       rec("wa", chat: true)]
        let s = CleanupCategory.sections(records)
        XCTAssertEqual(s[.screenshots]?.map(\.id), ["oldshot", "shot"]) // oldest first
        XCTAssertEqual(s[.largeVideos]?.map(\.id), ["bigger", "big"]) // biggest first, over 50 MB
        XCTAssertEqual(s[.accidental]?.map(\.id), ["oops"])
        XCTAssertEqual(Set(s[.moments]!.map(\.id)), ["clip", "unchecked"])
        XCTAssertEqual(s[.chats]?.map(\.id), ["wa"])
        XCTAssertEqual(CleanupCategory.allCases.filter(\.preselects), [.similar]) // only Similar shots pre-picks
    }

    func testChatFileNames() {
        for (name, app) in [("IMG-20240131-WA0012.jpg", "WhatsApp"), ("VID-20231224-WA0003.mp4", "WhatsApp"), ("img-20240131-wa12345.jpeg", "WhatsApp"),
                            ("telegram-cloud-photo-size-2-5321-y.jpg", "Telegram"), ("signal-2024-01-31-123456.jpg", "Signal"),
                            ("received_1234567890123456.jpeg", "Messenger"), ("photo_2024-01-31_12-34-56.jpg", "Telegram")] {
            XCTAssertEqual(AssetRecord.chatApp(fileName: name), app, name)
        }
        for name in ["IMG_1234.HEIC", "IMG_1234.JPG", "IMG_1234.MOV", "FullSizeRender.jpg", "Screenshot 2024-01-31.png",
                     "3F2504E0-4F89-11D3-9A0C-0305E82C3301.jpg", "3F2504E0-4F89-11D3-9A0C-0305E82C3301.mov", // other apps save these too
                     "IMG-2024-WA0012.jpg", "received.jpg", "my telegram-cloud.jpg", "photo_1.jpg"] {
            XCTAssertNil(AssetRecord.chatApp(fileName: name), name)
        }
    }

    func testChatAndSocialAlbumTitles() {
        for (title, app) in [("WhatsApp", "WhatsApp"), ("WhatsApp Business", "WhatsApp Business"), ("Telegram", "Telegram"),
                             ("Signal", "Signal"), ("Messenger", "Messenger"), ("Viber", "Viber"), ("WeChat", "WeChat"), ("LINE", "LINE"),
                             ("Instagram", "Instagram"), ("snapchat", "Snapchat"), ("Facebook", "Facebook"), ("TikTok", "TikTok"),
                             ("X", "X"), ("Twitter", "Twitter"), ("Pinterest", "Pinterest"), ("Threads", "Threads")] {
            XCTAssertEqual(AssetRecord.chatApp(albumTitle: title), app, title)
        }
        for title in ["Instagram Stories I like", "My WhatsApp", "Holidays", "Xmas", "", nil] as [String?] {
            XCTAssertNil(AssetRecord.chatApp(albumTitle: title), title ?? "nil") // whole titles only
        }
    }

    func testByteCountSumsResourcesElseEstimates() {
        XCTAssertEqual(AssetRecord.byteCount(resourceSizes: [3_000_000, 500_000], isVideo: false, width: 4032, height: 3024, duration: 0), 3_500_000)
        // Unknown (0): 12 MP photo ≈ 0.3 byte per pixel.
        XCTAssertEqual(AssetRecord.byteCount(resourceSizes: [0], isVideo: false, width: 4000, height: 3000, duration: 0), 3_600_000)
        XCTAssertEqual(AssetRecord.byteCount(resourceSizes: [], isVideo: false, width: 4000, height: 3000, duration: 0), 3_600_000)
        // 10 s of 1080p ≈ 9.3 Mbit/s → about 11.7 MB.
        let video = AssetRecord.byteCount(resourceSizes: [], isVideo: true, width: 1920, height: 1080, duration: 10)
        XCTAssertEqual(Double(video), 1920 * 1080 * 30 * 0.15 / 8 * 10, accuracy: 1)
    }
}

@MainActor
final class TrayTests: XCTestCase {
    private var url: URL!

    override func setUp() async throws {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/tray.json")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    func testPreselectionSkipsGuardedItemsAndOnlyOffersOnce() {
        let tray = DeleteTray(file: url)
        let items = [rec("plain", screenshot: true), rec("fav", favorite: true), rec("edited", edited: true),
                     rec("album", album: true)]
        tray.preselect(items)
        XCTAssertEqual(tray.ids, ["plain"])
        tray.remove(["plain"]) // the user keeps it
        tray.preselect(items)
        XCTAssertEqual(tray.ids, [], "an item taken out isn't put back")
        tray.preselect(items + [rec("new", screenshot: true)])
        XCTAssertEqual(tray.ids, ["new"], "new items are offered")
    }

    func testSelectAllSkipsGuardedAndSensitiveItems() {
        var passport = rec("passport")
        passport.sensitive = "Passport or ID"
        var checked = rec("checked")
        checked.sensitive = "" // checked, nothing found
        let items = [rec("a"), rec("fav", favorite: true), rec("b"), rec("album", album: true), rec("edit", edited: true), passport, checked]
        XCTAssertEqual(DeleteTray.selectable(items), ["a", "b", "checked"])
    }

    func testSimilarSelectAllNeverPicksAGroupsKeeper() {
        func shot(_ id: String, at t: TimeInterval, sharpness: Double, favorite: Bool = false) -> AssetRecord {
            var r = rec(id, modified: t, favorite: favorite)
            r.sharpness = sharpness
            r.similarPrev = ""
            return r
        }
        var b = shot("b", at: 10, sharpness: 300), c = shot("c", at: 20, sharpness: 50)
        b.similarPrev = "a"; b.similarToPrev = true
        c.similarPrev = "b"; c.similarToPrev = true
        var e = shot("e", at: 1010, sharpness: 50)
        e.similarPrev = "d"; e.similarToPrev = true
        let items = [shot("a", at: 0, sharpness: 50), b, c, shot("d", at: 1000, sharpness: 300), e]
        let tray = DeleteTray(file: url)
        var groups = tray.keeperFirst(SimilarShots.groups(items))
        XCTAssertEqual(Set(groups.map(\.[0].id)), ["b", "d"], "the sharpest of each group is its best")
        XCTAssertEqual(Set(DeleteTray.selectable(items, groups: groups)), ["a", "c", "e"])

        // The user makes "a" the keeper: it leaves the tray, "b" goes in, and Select All now spares "a", not "b".
        tray.add(["a"])
        tray.makeKeeper("a", in: groups.first { $0.contains { $0.id == "a" } }!)
        XCTAssertEqual(tray.ids, ["b"])
        groups = DeleteTray(file: url).keeperFirst(SimilarShots.groups(items)) // the pick is saved
        XCTAssertEqual(Set(groups.map(\.[0].id)), ["a", "d"])
        XCTAssertEqual(Set(DeleteTray.selectable(items, groups: groups)), ["b", "c", "e"])
    }

    func testHistoryRecordsEachDelete() {
        let file = url.deletingLastPathComponent().appending(path: "history.json")
        XCTAssertEqual(CleanerHistory.load(file), [])
        CleanerHistory.record(.init(date: Date(timeIntervalSince1970: 1), bytes: 5_000_000, count: 3), to: file)
        CleanerHistory.record(.init(date: Date(timeIntervalSince1970: 2), bytes: 7_000_000, count: 4), to: file)
        let saved = CleanerHistory.load(file)
        XCTAssertEqual(saved.map(\.bytes), [5_000_000, 7_000_000])
        XCTAssertEqual(saved.map(\.count), [3, 4])
        XCTAssertEqual(saved.last?.date, Date(timeIntervalSince1970: 2))
    }

    func testPreselectionNeverPicksSensitiveItems() {
        var card = rec("card")
        card.sensitive = "Card number"
        let tray = DeleteTray(file: url)
        tray.preselect([card, rec("plain")])
        XCTAssertEqual(tray.ids, ["plain"])
    }

    func testTrayPersists() {
        let tray = DeleteTray(file: url)
        tray.add(["x", "y"])
        tray.toggle("y")
        tray.preselect([rec("z")])
        let reopened = DeleteTray(file: url)
        XCTAssertEqual(reopened.ids, ["x", "z"])
        XCTAssertEqual(reopened.state.offered, ["z"])
    }
}

/// Runs the real scanner on the simulator's photo library (needs full access and at least two items; see README).
final class ScannerResumeTests: XCTestCase {
    func testStoppedScanSavesAndTheNextOneResumes() async throws {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, PHAsset.fetchAssets(with: nil).count >= 2 else {
            throw XCTSkip("Needs full Photos access and 2+ items in the simulator's library (see README).")
        }
        let total = PHAsset.fetchAssets(with: nil).count
        // 1. Stop the scan right after its first item, as background expiry does (it cancels the scan's task).
        var saved: ScanCache?
        let stopped = await Task {
            await LibraryScanner.scan(ScanCache(), checkpoint: { saved = $0 }, progress: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }.value
        let checkpoint = try XCTUnwrap(saved, "a stopped scan saves what it has")
        XCTAssertEqual(checkpoint.records.count, 1)
        XCTAssertNil(checkpoint.token, "an unfinished full pass has no token, so the next scan resumes the pass")
        XCTAssertEqual(stopped.records, checkpoint.records)

        // 2. Resume from the saved cache. Mark the saved record so we can tell it was reused rather than re-read.
        var resumed = checkpoint
        let firstID = try XCTUnwrap(resumed.records.keys.first)
        resumed.records[firstID]!.bytes = -42
        let done = await LibraryScanner.scan(resumed, checkpoint: { _ in }, progress: { _, _ in })
        XCTAssertEqual(done.records.count, total)
        XCTAssertNotNil(done.token)
        XCTAssertEqual(done.records[firstID]?.bytes, -42, "the record from the stopped scan is reused, not re-read")
        XCTAssertTrue(done.records.values.filter { $0.id != firstID }.allSatisfy { $0.bytes > 0 })

        // 3. With a token, the next scan is incremental and changes nothing.
        let again = await LibraryScanner.scan(done, checkpoint: { _ in }, progress: { _, _ in })
        XCTAssertEqual(again.records, done.records)
    }
}
