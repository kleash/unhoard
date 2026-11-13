import BackgroundTasks
import Photos

/// One cached photo-library asset: plain data, so the scan can be saved and resumed.
/// Analysis fields are optional (nil = not analysed yet); add new ones next to `accident` and to `carryAnalysis`.
struct AssetRecord: Codable, Hashable, Identifiable {
    var id: String // PHAsset.localIdentifier
    var modified: Date?
    var created: Date?
    var mediaType: Int // PHAssetMediaType.rawValue
    var subtypes: UInt // PHAssetMediaSubtype.rawValue
    var duration: Double
    var width: Int
    var height: Int
    var isFavorite: Bool
    var hasAdjustments: Bool
    var inUserAlbum: Bool
    var isBurst: Bool
    var isScreenRecording: Bool
    /// The chat or social app it was saved from (its album, or its file name), nil when none.
    var chatApp: String?
    /// The size of the asset's files, or an estimate when PhotoKit doesn't say (see `byteCount`).
    var bytes: Int64
    /// Short clips only: true when every sampled frame is black, dark or uniform.
    var accident: Bool?
    // Photo analysis on a local thumbnail (see PhotoAnalysis.swift); nil = not analysed yet.
    /// Laplacian variance (see `PhotoAnalysis.sharpness`); set once the photo pass has run, so it marks "analysed".
    var sharpness: Double?
    /// Mean luma, 0...1.
    var brightness: Double?
    /// The best face capture quality (0...1), nil when there are no faces.
    var faceQuality: Float?
    /// iOS 26+: lens-smudge confidence (0...1).
    var smudge: Float?
    /// Vision's aesthetics score (-1...1) and utility flag; nil where the request can't run (the simulator).
    var score: Float?
    var isUtility: Bool?
    /// "" = checked and nothing found (or not a candidate); otherwise why it looks sensitive.
    var sensitive: String?
    /// The previous photo in time it was compared with ("" = none), and whether they look alike (Similar shots).
    var similarPrev: String?
    var similarToPrev: Bool?
    /// AI second opinion: "memory", "utility" or "accident", with a one-line reason.
    var aiLabel: String?
    var aiReason: String?
    /// Claude's Similar-shots opinion: "keep" or "duplicate", with a one-line reason.
    var similarLabel: String?
    var similarReason: String?

    var isVideo: Bool { mediaType == PHAssetMediaType.video.rawValue }
    var isPhoto: Bool { mediaType == PHAssetMediaType.image.rawValue }
    var fromChat: Bool { chatApp != nil }
    var isSensitive: Bool { !(sensitive ?? "").isEmpty }
    var isScreenshot: Bool { PHAssetMediaSubtype(rawValue: subtypes).contains(.photoScreenshot) }
    var isShortClip: Bool { isVideo && duration < 3 }
    /// The memory guard: favourites, edited items and items in the user's own albums are never selected for the user.
    var isGuarded: Bool { isFavorite || hasAdjustments || inUserAlbum }
    /// Never picked by Select All, a drag or pre-selection: the memory guard, and sensitive items (hide or tap them one by one).
    var isKeptFromBulk: Bool { isGuarded || isSensitive }

    /// Keeps analysis results from the cached record of the same, unchanged asset.
    mutating func carryAnalysis(from old: AssetRecord) {
        accident = old.accident
        sharpness = old.sharpness
        brightness = old.brightness
        faceQuality = old.faceQuality
        smudge = old.smudge
        score = old.score
        isUtility = old.isUtility
        sensitive = old.sensitive
        similarPrev = old.similarPrev
        similarToPrev = old.similarToPrev
        aiLabel = old.aiLabel
        aiReason = old.aiReason
        similarLabel = old.similarLabel
        similarReason = old.similarReason
    }
}

extension AssetRecord {
    /// Reads the asset's resources too (sizes and file names), which is the slow part of a scan.
    init(_ a: PHAsset, inUserAlbum: Bool, inScreenRecordings: Bool, chatAlbumApp: String?) {
        let resources = PHAssetResource.assetResources(for: a)
        id = a.localIdentifier
        modified = a.modificationDate
        created = a.creationDate
        mediaType = a.mediaType.rawValue
        subtypes = a.mediaSubtypes.rawValue
        duration = a.duration
        width = a.pixelWidth
        height = a.pixelHeight
        isFavorite = a.isFavorite
        hasAdjustments = a.hasAdjustments
        self.inUserAlbum = inUserAlbum
        isBurst = a.burstIdentifier != nil
        isScreenRecording = a.mediaSubtypes.contains(.videoScreenRecording) || inScreenRecordings
        chatApp = chatAlbumApp ?? resources.lazy.compactMap { Self.chatApp(fileName: $0.originalFilename) }.first
        bytes = Self.byteCount(resourceSizes: resources.map(Self.fileSize), isVideo: a.mediaType == .video,
                               width: a.pixelWidth, height: a.pixelHeight, duration: a.duration)
    }

    /// shortcut: undocumented PhotoKit key "fileSize" (the user chose it knowingly); it may break or be flagged in App Review,
    /// then switch to `byteCount`'s estimate alone. Checked with responds(to:) first, so a removed key reads as unknown, not a crash.
    static func fileSize(_ resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: NSSelectorFromString("fileSize")) else { return 0 }
        return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }

    /// The resources' total size; when unknown (0), an estimate: photos ~0.3 byte per pixel (HEIC/JPEG),
    /// videos at ~0.15 bit per pixel per frame at 30 fps (about 9 Mbit/s at 1080p, 37 at 4K).
    static func byteCount(resourceSizes: [Int64], isVideo: Bool, width: Int, height: Int, duration: Double) -> Int64 {
        let total = resourceSizes.reduce(0, +)
        if total > 0 { return total }
        let pixels = Double(width) * Double(height)
        return Int64(isVideo ? pixels * 30 * 0.15 / 8 * duration : pixels * 0.3)
    }

    /// Albums that chat and social apps create when they save to Photos (matched case-insensitively, whole title), with the app's name.
    static let chatAlbumApps: [String: String] = [
        "whatsapp": "WhatsApp", "whatsapp business": "WhatsApp Business", "telegram": "Telegram", "signal": "Signal",
        "messenger": "Messenger", "viber": "Viber", "wechat": "WeChat", "line": "LINE", "instagram": "Instagram",
        "snapchat": "Snapchat", "facebook": "Facebook", "tiktok": "TikTok", "x": "X", "twitter": "Twitter",
        "pinterest": "Pinterest", "threads": "Threads",
    ]

    static func chatApp(albumTitle: String?) -> String? { chatAlbumApps[(albumTitle ?? "").lowercased()] }

    /// File names chat apps give saved media. Conservative: each rule is one app's own pattern.
    /// - `IMG-20240131-WA0012.jpg`, `VID-…-WA…` (WhatsApp, Android-made media forwarded to the iPhone)
    /// - `telegram-cloud-…` (Telegram), `signal-2024-01-31-…` (Signal), `received_1234567890….jpeg` (Messenger)
    /// - `photo_2024-01-31_12-34-56.jpg` (Telegram Desktop exports)
    /// Not used: bare UUID names (`<UUID>.jpg`, as WhatsApp on iOS saves). Other apps save the same way (Liveloom's
    /// Live Photo stills are `<UUID>.jpg`), so WhatsApp's iOS saves are found through its album instead.
    static func chatApp(fileName name: String) -> String? {
        let rules: [(Regex<Substring>, String)] = [
            (#/(?i)^(?:IMG|VID|AUD|PTT|STK)-\d{8}-WA\d{4,}\.\w+$/#, "WhatsApp"),
            (#/(?i)^telegram-(?:cloud|peer)-/#, "Telegram"),
            (#/(?i)^signal-\d{4}-\d{2}-\d{2}-/#, "Signal"),
            (#/(?i)^received_\d{8,}\.\w+$/#, "Messenger"),
            (#/(?i)^photo_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}/#, "Telegram"),
        ]
        return rules.first { name.firstMatch(of: $0.0) != nil }?.1
    }
}

/// A home-screen category. Add a case (and its title, symbol, blurb, filter and order) for a new one.
enum CleanupCategory: String, CaseIterable, Identifiable, Codable {
    case screenshots, similar, blurry, utility, sensitive, largeVideos, accidental, moments, chats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: "Screenshots & Recordings"
        case .similar: "Similar Shots"
        case .blurry: "Blurry"
        case .utility: "Utility Shots"
        case .sensitive: "Sensitive"
        case .largeVideos: "Large Videos"
        case .accidental: "Accidental Clips"
        case .moments: "Short Moments"
        case .chats: "Saved from Apps"
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .similar: "square.on.square"
        case .blurry: "camera.metering.unknown"
        case .utility: "doc.text.viewfinder"
        case .sensitive: "lock.shield"
        case .largeVideos: "film.stack"
        case .accidental: "hand.raised.slash"
        case .moments: "sparkles.rectangle.stack"
        case .chats: "bubble.left.and.bubble.right"
        }
    }

    var blurb: String {
        switch self {
        case .screenshots: "Oldest first."
        case .similar: "Photos taken moments apart that look alike. The best of each group is kept; the rest are selected for you."
        case .blurry: "Photos with nothing in focus, blurriest first. Dark and night shots are left out."
        case .utility: "Receipts, labels, whiteboards, screens and other photos taken to remember something. Lowest score first."
        case .sensitive: "Passports, IDs, cards, passes, prescriptions and passwords. Hide them in the Face ID-locked Hidden album."
        case .largeVideos: "Videos over 50 MB, biggest first."
        case .accidental: "Clips under 3 seconds that look black, dark or covered."
        case .moments: "Other clips under 3 seconds. Turn the good ones into stills."
        case .chats: "Photos and videos saved from WhatsApp, Instagram, Telegram and other apps. Biggest first."
        }
    }

    /// Whether opening it puts its unguarded items in the tray for review: Similar shots only (all but each group's best).
    /// On a real library ~20% of "junk" were memories, so nothing else is pre-picked.
    var preselects: Bool { self == .similar }

    /// Similar shots are grouped by `SimilarShots.groups` in `sections`, not record by record.
    func includes(_ r: AssetRecord) -> Bool {
        switch self {
        case .screenshots: r.isScreenshot || r.isScreenRecording
        case .similar: false
        case .blurry: r.isPhoto && !r.isScreenshot && !r.isSensitive && PhotoAnalysis.isBlurry(r)
        case .utility: r.isPhoto && !r.isScreenshot && !r.isSensitive && PhotoAnalysis.isLowScore(r)
        case .sensitive: r.isSensitive
        case .largeVideos: r.isVideo && r.bytes >= 50_000_000
        case .accidental: r.isShortClip && r.accident == true
        case .moments: r.isShortClip && r.accident != true
        case .chats: r.fromChat
        }
    }

    func ordered(_ a: AssetRecord, _ b: AssetRecord) -> Bool {
        switch self {
        case .largeVideos, .chats: a.bytes > b.bytes
        case .screenshots: (a.created ?? .distantPast) < (b.created ?? .distantPast)
        case .blurry: (a.sharpness ?? 0) < (b.sharpness ?? 0)
        // The AI's accidents and utility shots first, its memories last; lowest score first within each.
        case .utility: (Self.aiRank(a), a.score ?? 0) < (Self.aiRank(b), b.score ?? 0)
        case .accidental, .moments, .similar, .sensitive: (a.created ?? .distantPast) > (b.created ?? .distantPast)
        }
    }

    private static func aiRank(_ r: AssetRecord) -> Int { ["accident": 0, "utility": 1, "memory": 3][r.aiLabel ?? ""] ?? 2 }

    /// A short label on each thumbnail, if the category has one.
    func caption(_ r: AssetRecord) -> String? {
        switch self {
        case .chats: r.chatApp
        case .sensitive: r.sensitive
        case .utility: r.aiLabel?.capitalized
        case .similar: r.similarLabel.map { "Claude: \($0)" }
        default: nil
        }
    }

    static func sections(_ records: some Collection<AssetRecord>) -> [CleanupCategory: [AssetRecord]] {
        var out = Dictionary(uniqueKeysWithValues: allCases.map { ($0, [AssetRecord]()) })
        for r in records { for c in allCases where c.includes(r) { out[c]!.append(r) } }
        for c in allCases { out[c]!.sort(by: c.ordered) }
        out[.similar] = SimilarShots.groups(records).flatMap { $0 }
        return out
    }
}

/// The scan cache, one file in Application Support.
struct ScanCache: Codable {
    var records: [String: AssetRecord] = [:]
    /// The archived PHPersistentChangeToken of the last complete scan; nil until a full pass has finished.
    var token: Data?
    /// True when Vision's aesthetics request can't run here (the simulator, say), as of the last scan.
    var aestheticsUnsupported: Bool?
    /// The version of the detection rules the records were made with; nil in caches from before rules were versioned.
    var rules: Int? = ScanCache.currentRules

    /// 2: stricter "ID with photo", Similar distance 0.35 → 0.15.
    static let currentRules = 2

    /// Clears what older rules decided, so the next scan redoes just that (keeps everything else).
    mutating func upgradeRules() {
        guard (rules ?? 1) < Self.currentRules else { return }
        for id in records.keys {
            if records[id]!.sensitive == "ID with photo" { records[id]!.sensitive = nil }
            records[id]!.similarPrev = nil
            records[id]!.similarToPrev = nil
        }
        rules = Self.currentRules
    }

    static func load(_ url: URL) -> ScanCache? {
        (try? Data(contentsOf: url)).flatMap { try? PropertyListDecoder().decode(ScanCache.self, from: $0) }
    }

    func save(to url: URL) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The records after a scan: `fresh` replace cached ones (keeping analysis when the asset is unchanged) and `deleted` go.
    /// A full pass lists every asset, so it also drops whatever it didn't see.
    static func merge(_ old: [String: AssetRecord], fresh: [AssetRecord], deleted: Set<String>, fullPass: Bool) -> [String: AssetRecord] {
        var out = fullPass ? [:] : old
        for var r in fresh {
            if let o = old[r.id], o.modified == r.modified { r.carryAnalysis(from: o) }
            out[r.id] = r
        }
        for id in deleted { out[id] = nil }
        return out
    }
}

/// Brings a ScanCache up to date with the photo library. Runs off the main thread.
enum LibraryScanner {
    static let checkpointInterval: TimeInterval = 3

    /// Cancelling the calling task stops the scan early: it checkpoints what it has and returns, and the next scan resumes from there.
    static func scan(_ start: ScanCache, checkpoint: (ScanCache) async -> Void, progress: (String, Double) async -> Void) async -> ScanCache {
        var cache = start
        let token = PHPhotoLibrary.shared().currentChangeToken // taken first, so changes during the scan show up next time
        // Albums chat apps make count as chat saves, not as the user's own albums (which the memory guard protects).
        let albums = assetIDs(in: .album, .albumRegular) { AssetRecord.chatApp(albumTitle: $0.localizedTitle) == nil }
        var chatAlbums: [String: String] = [:] // asset id → app
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in
            guard let app = AssetRecord.chatApp(albumTitle: c.localizedTitle) else { return }
            PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in chatAlbums[a.localIdentifier] = app }
        }
        let recordings = assetIDs(in: .smartAlbum, .smartAlbumScreenRecordings)
        func record(_ a: PHAsset) -> AssetRecord {
            let id = a.localIdentifier
            return AssetRecord(a, inUserAlbum: albums.contains(id), inScreenRecordings: recordings.contains(id), chatAlbumApp: chatAlbums[id])
        }

        if let (changed, deleted) = changes(since: cache.token) {
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: Array(changed), options: nil)
            var fresh: [AssetRecord] = []
            fetched.enumerateObjects { a, _, _ in fresh.append(record(a)) }
            // Changed assets that no longer fetch (hidden, say) leave the cache too.
            let gone = deleted.union(changed.subtracting(fresh.map(\.id)))
            cache.records = ScanCache.merge(cache.records, fresh: fresh, deleted: gone, fullPass: false)
        } else {
            let all = PHAsset.fetchAssets(with: nil)
            var fresh: [AssetRecord] = []
            fresh.reserveCapacity(all.count)
            var lastSave = Date()
            let started = Date()
            for i in 0..<all.count {
                if Task.isCancelled { // stopped (background time ran out): keep what's done, still without a token
                    let partial = ScanCache(records: ScanCache.merge(cache.records, fresh: fresh, deleted: [], fullPass: false))
                    await checkpoint(partial)
                    return partial
                }
                let a = all.object(at: i)
                // Unchanged since the cached record (say, from a scan that was killed): skip re-reading its resources.
                if var old = cache.records[a.localIdentifier], old.modified == a.modificationDate {
                    old.isFavorite = a.isFavorite
                    old.hasAdjustments = a.hasAdjustments
                    fresh.append(old)
                } else {
                    fresh.append(record(a))
                }
                if i % 250 == 0 { await progress(progressText(.reading, i, all.count, since: started), ScanStep.reading.overall(i, all.count)) }
                if Date().timeIntervalSince(lastSave) > checkpointInterval { // resumable: a relaunch keeps these records
                    await checkpoint(ScanCache(records: ScanCache.merge(cache.records, fresh: fresh, deleted: [], fullPass: false)))
                    lastSave = Date()
                }
            }
            cache.records = ScanCache.merge(cache.records, fresh: fresh, deleted: [], fullPass: true)
        }
        // Album membership changes without the asset changing, so refresh it for every record.
        for id in cache.records.keys {
            cache.records[id]!.inUserAlbum = albums.contains(id)
            if recordings.contains(id) { cache.records[id]!.isScreenRecording = true }
            if let app = chatAlbums[id] { cache.records[id]!.chatApp = app }
        }
        cache.token = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        await checkpoint(cache)

        let pending = cache.records.values.filter { $0.isShortClip && $0.accident == nil }.map(\.id)
        var lastSave = Date()
        let started = Date()
        for (n, id) in pending.enumerated() {
            if Task.isCancelled { break } // the rest stay unchecked (nil) for the next scan
            await progress(progressText(.clips, n, pending.count, since: started), ScanStep.clips.overall(n, pending.count))
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                  let video = try? await ClipTools.avAsset(asset, fast: true) else { continue } // retried next scan
            cache.records[id]?.accident = (try? await ClipTools.isAccident(video)) ?? false
            if Date().timeIntervalSince(lastSave) > checkpointInterval { await checkpoint(cache); lastSave = Date() }
        }
        if !pending.isEmpty { await checkpoint(cache) }
        if !Task.isCancelled { await PhotoAnalysis.run(&cache, checkpoint: checkpoint, progress: progress) }
        return cache
    }

    /// "Step 3 of 4 · Looking at each photo", a newline, then "13% · 1,234 of 9,876 · about 2 min left" (the estimate
    /// once there's enough to go on). `resumedAt` is how many were already done when this run started (the estimate uses
    /// only this run's pace).
    static func progressText(_ step: ScanStep, _ done: Int, _ total: Int, since start: Date, resumedAt: Int = 0) -> String {
        let f = Double(done) / Double(max(total, 1))
        var text = "Step \(step.rawValue) of \(ScanStep.allCases.count) · \(step.title)\n\(Int(f * 100))% · \(done.formatted()) of \(total.formatted())"
        let elapsed = Date().timeIntervalSince(start), thisRun = done - resumedAt
        if Double(thisRun) / Double(max(total - resumedAt, 1)) > 0.01, elapsed > 2 {
            let left = Duration.seconds(elapsed * Double(total - done) / Double(thisRun))
            text += " · about \(left.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))) left"
        }
        return text
    }

    /// The scan's passes, in order, so people see there's more to come after the first bar fills.
    enum ScanStep: Int, CaseIterable {
        case reading = 1, clips, photos, similar

        var title: String {
            switch self {
            case .reading: "Reading your library"
            case .clips: "Checking short clips"
            case .photos: "Looking at each photo"
            case .similar: "Grouping similar shots"
            }
        }

        /// Where the step sits in the whole scan, by its usual share of the time.
        var span: (start: Double, width: Double) {
            switch self {
            case .reading: (0, 0.1)
            case .clips: (0.1, 0.05)
            case .photos: (0.15, 0.6)
            case .similar: (0.75, 0.25)
            }
        }

        /// The whole scan's fraction when this step is `done` of `total` through.
        func overall(_ done: Int, _ total: Int) -> Double { span.start + span.width * min(1, Double(done) / Double(max(total, 1))) }

        /// How far through this step a whole-scan `fraction` is, 0...1.
        func fill(_ fraction: Double) -> Double { min(1, max(0, (fraction - span.start) / span.width)) }
    }

    /// Changed (inserted or updated) and deleted asset ids since `data`'s token, or nil when a full pass is needed.
    static func changes(since data: Data?) -> (changed: Set<String>, deleted: Set<String>)? {
        guard let data, let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data),
              let changes = try? PHPhotoLibrary.shared().fetchPersistentChanges(since: token) else { return nil }
        var changed = Set<String>(), deleted = Set<String>()
        for change in changes {
            guard let d = try? change.changeDetails(for: .asset) else { return nil }
            changed.formUnion(d.insertedLocalIdentifiers)
            changed.formUnion(d.updatedLocalIdentifiers)
            deleted.formUnion(d.deletedLocalIdentifiers)
        }
        return (changed.subtracting(deleted), deleted)
    }

    /// Every asset id in the collections of one type and subtype (that pass `include`), fetched once per scan.
    static func assetIDs(in type: PHAssetCollectionType, _ subtype: PHAssetCollectionSubtype,
                         where include: @escaping (PHAssetCollection) -> Bool = { _ in true }) -> Set<String> {
        var ids = Set<String>()
        PHAssetCollection.fetchAssetCollections(with: type, subtype: subtype, options: nil).enumerateObjects { c, _, _ in
            guard include(c) else { return }
            PHAsset.fetchAssets(in: c, options: nil).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
        }
        return ids
    }
}

/// The cleaner's view of the photo library: cached records, their categories and the scan's progress.
@MainActor @Observable final class CleanerLibrary {
    private(set) var records: [String: AssetRecord] = [:]
    private(set) var sections: [CleanupCategory: [AssetRecord]] = [:]
    /// What the running scan is doing, nil when idle.
    private(set) var status: String?
    private(set) var fraction = 0.0
    /// Vision's aesthetics request can't run here, so Utility shots needs an iPhone.
    private(set) var aestheticsUnsupported = false
    /// Items the scan has just read or analysed, newest first (the home screen's live mosaic); never sensitive ones.
    private(set) var recent: [String] = []
    /// Thumbnails and previews for every view of the cleaner.
    @ObservationIgnored let images = PHCachingImageManager()
    @ObservationIgnored private var token: Data?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<ScanCache, Never>?
    @ObservationIgnored var continuedTask: BGTask? // iOS 26+: the system's progress UI for this scan
    @ObservationIgnored private var deleted = Set<String>() // so a scan that started before a delete doesn't bring items back
    @ObservationIgnored let file: URL
    /// The detection rules changed since the cache was made: what they pre-selected should be offered afresh.
    @ObservationIgnored var rulesChanged = false
    /// Claude's Similar-shots run (see `askClaude`): groups done of total while it goes, and why it stopped if it failed.
    var similarRun: (done: Int, total: Int)?
    var similarError: String?
    @ObservationIgnored var similarTask: Task<Void, Never>?

    init(file: URL = URL.applicationSupportDirectory.appending(path: "Unhoard/library.plist")) {
        self.file = file
        if var cache = ScanCache.load(file) {
            if (cache.rules ?? 1) < ScanCache.currentRules {
                cache.upgradeRules()
                cache.save(to: file)
                rulesChanged = true
            }
            apply(cache, CleanupCategory.sections(cache.records.values))
        }
    }

    var hasCompletedScan: Bool { token != nil }

    /// A full pass hasn't finished, or short clips or photos are still unchecked.
    var isUnfinished: Bool {
        token == nil || records.values.contains { ($0.isShortClip && $0.accident == nil) || PhotoAnalysis.needsWork($0, aesthetics: !aestheticsUnsupported) }
    }

    /// Scans (incrementally after the first complete pass); waits for a scan already running.
    /// Keeps going in the background as far as iOS allows (see CleanerBackground.swift).
    func scan() async {
        if let running { return await running.value }
        let start = ScanCache(records: records, token: token, aestheticsUnsupported: aestheticsUnsupported), file = file
        let finishBackground = keepScanAlive(long: isUnfinished)
        let worker = Task.detached(priority: .userInitiated) {
            await LibraryScanner.scan(start, checkpoint: { cache in
                cache.save(to: file)
                let sections = CleanupCategory.sections(cache.records.values) // sorted here, off the main thread
                await self.apply(cache, sections)
            }, progress: { text, f in
                await MainActor.run {
                    self.status = text
                    self.fraction = f
                    self.reportBackgroundProgress(text, f)
                }
            })
        }
        self.worker = worker
        let task = Task {
            let done = await worker.value
            apply(done, CleanupCategory.sections(done.records.values))
            status = nil
            finishBackground(!isUnfinished)
        }
        running = task
        await task.value
        running = nil
        self.worker = nil
    }

    var isScanning: Bool { worker != nil }

    /// Stops a running scan early; it saves what it has and the next scan resumes from there.
    func stopScan() { worker?.cancel() }

    /// Drops deleted (or hidden) items from the cache.
    func remove(_ ids: some Sequence<String>) {
        deleted.formUnion(ids)
        apply(ScanCache(records: records, token: token, aestheticsUnsupported: aestheticsUnsupported), sections)
        save()
    }

    /// Stores AI second opinions (id → label and reason): Utility ones, or Claude's Similar-shots ones when `similar`.
    func setOpinions(_ opinions: [String: (label: String, reason: String)], similar: Bool = false) {
        for (id, o) in opinions where records[id] != nil {
            if similar {
                records[id]!.similarLabel = o.label
                records[id]!.similarReason = o.reason
            } else {
                records[id]!.aiLabel = o.label
                records[id]!.aiReason = o.reason
            }
        }
        sections = CleanupCategory.sections(records.values)
        save()
    }

    private func save() { ScanCache(records: records, token: token, aestheticsUnsupported: aestheticsUnsupported).save(to: file) }

    private func apply(_ cache: ScanCache, _ sections: [CleanupCategory: [AssetRecord]]) {
        let deleted = deleted
        // AI opinions arrive while a scan may be running from an older copy of the records: keep them over it.
        var incoming = cache.records
        var kept = false
        for (id, old) in records where incoming[id] != nil && incoming[id]?.modified == old.modified
            && (old.aiLabel != nil && incoming[id]?.aiLabel == nil || old.similarLabel != nil && incoming[id]?.similarLabel == nil) {
            if incoming[id]!.aiLabel == nil { (incoming[id]!.aiLabel, incoming[id]!.aiReason) = (old.aiLabel, old.aiReason) }
            if incoming[id]!.similarLabel == nil { (incoming[id]!.similarLabel, incoming[id]!.similarReason) = (old.similarLabel, old.similarReason) }
            kept = true
        }
        let fresh = incoming.values.lazy.filter { r in
            !r.isSensitive && !deleted.contains(r.id) && (self.records[r.id].map { $0.sharpness == nil && r.sharpness != nil } ?? true)
        }.prefix(16).map(\.id)
        if !fresh.isEmpty { recent = Array((fresh + recent).prefix(24)) }
        records = deleted.isEmpty ? incoming : incoming.filter { !deleted.contains($0.key) }
        token = cache.token
        if let unsupported = cache.aestheticsUnsupported { aestheticsUnsupported = unsupported } // partial checkpoints don't know yet
        self.sections = kept ? CleanupCategory.sections(records.values)
            : deleted.isEmpty ? sections : sections.mapValues { $0.filter { !deleted.contains($0.id) } }
        // Regroup what's left: a Similar keeper whose shots were all deleted is in no group any more, so it leaves Similar.
        if !deleted.isEmpty { self.sections[.similar] = SimilarShots.groups(self.sections[.similar] ?? []).flatMap { $0 } }
        if kept { save() }
    }
}

extension CleanerLibrary {
    /// A line to share once a finished scan with full access has counted 500+ photo screenshots (recordings aren't counted).
    var screenshotCountLine: String? {
        guard status == nil, hasCompletedScan, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return nil }
        let shots = (sections[.screenshots] ?? []).filter(\.isScreenshot)
        return Self.countLine(count: shots.count, oldest: shots.compactMap(\.created).min())
    }

    /// The count and the oldest one's month and year only: never photos, sizes or other categories. Nil under 500.
    nonisolated static func countLine(count: Int, oldest: Date?, locale: Locale = .current) -> String? {
        guard count >= 500 else { return nil }
        let since = oldest.map { " The oldest is from \($0.formatted(.dateTime.month(.wide).year().locale(locale)))." } ?? ""
        return "I have \(count.formatted(.number.locale(locale))) screenshots on my iPhone.\(since) "
            + "Counted on my phone by Unhoard (free, nothing uploaded): https://kleash.github.io/unhoard/"
    }
}
