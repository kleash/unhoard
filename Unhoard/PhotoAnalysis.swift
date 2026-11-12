import Photos
import UIKit
import Vision

/// Photo analysis on local thumbnails (never originals, never the network): sharpness, faces, lens smudge, Vision's
/// aesthetics score, the sensitive check and similar-shot links. Results live on AssetRecord, so `run` only does what's
/// missing and a stopped run resumes. README "How the categories are chosen" explains the thresholds.
enum PhotoAnalysis {
    /// Vision's aesthetics score runs -1...1; below 0 (the midpoint) counts as low. Apple's private Photos score isn't
    /// available, so this is a fresh choice on Vision's scale: on sample pictures, real scenes scored 0.45–0.9, a receipt 0.1
    /// (and isUtility), flat graphics -0.2 to -0.4. Utility shots are mostly caught by `isUtility`; the score adds the
    /// poorly made rest. shortcut: not calibrated on a real library yet; tune on device with the AI second opinion's labels.
    static let lowScore: Float = 0
    /// Sharpness below this is blurry (variance of the Laplacian, 0–255 grey, sharpest tile or face at 512 px; sharp
    /// photos measure in the hundreds or more). shortcut: a conservative first guess, not tuned on a real library.
    static let blurryBelow = 40.0
    /// Up to this sharpness, a lens-smudge confidence of `smudgeVote` or more (iOS 26+) also counts as blurry.
    static let smudgeBelow = 80.0, smudgeVote: Float = 0.7
    /// Mean luma below this is a dark or night shot, where sensor noise fakes sharpness; these are never called blurry.
    static let darkBelow = 0.15
    static let analysisSide: CGFloat = 512, textSide: CGFloat = 1024

    static func isLowScore(_ r: AssetRecord) -> Bool { r.isUtility == true || (r.score.map { $0 < lowScore } ?? false) }

    static func isBlurry(_ r: AssetRecord) -> Bool {
        guard let s = r.sharpness, let b = r.brightness, b >= darkBelow else { return false }
        return s < blurryBelow || (s < smudgeBelow && (r.smudge ?? 0) >= smudgeVote)
    }

    /// Whether `run` still has per-photo work for `r` (similar links are checked separately).
    static func needsWork(_ r: AssetRecord, aesthetics: Bool) -> Bool {
        r.isPhoto && (r.sharpness == nil || (aesthetics && r.score == nil) || r.sensitive == nil)
    }

    /// The photo passes, after the scan's metadata and short-clip passes. Cancelling stops early, keeping what's done.
    static func run(_ cache: inout ScanCache, checkpoint: (ScanCache) async -> Void, progress: (String, Double) async -> Void) async {
        let aesthetics = await aestheticsScore(probe) != nil
        cache.aestheticsUnsupported = !aesthetics
        let photos = cache.records.values.filter(\.isPhoto).sorted { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        let todo = photos.filter { needsWork($0, aesthetics: aesthetics) }
        let doneBefore = photos.count - todo.count // progress counts the whole library, so a resumed scan carries on from there
        var lastSave = Date()
        var started = Date()
        await withTaskGroup(of: AssetRecord?.self) { group in
            var next = 0, n = 0
            func feed() {
                guard next < todo.count, !Task.isCancelled else { return }
                let r = todo[next]
                next += 1
                group.addTask { await analysed(r, aesthetics: aesthetics) }
            }
            for _ in 0..<parallel { feed() } // the Neural Engine and thumbnail decoding overlap, so a few at once is faster
            while let result = await group.next() {
                n += 1
                if let r = result { cache.records[r.id] = r } // nil: no local thumbnail, retried next scan
                if n % 10 == 0 {
                    let done = doneBefore + n
                    await progress(LibraryScanner.progressText("Analysing photos", done, photos.count, since: started, resumedAt: doneBefore),
                                   Double(done) / Double(photos.count))
                }
                if Date().timeIntervalSince(lastSave) > LibraryScanner.checkpointInterval { await checkpoint(cache); lastSave = Date() }
                feed()
            }
        }
        await checkpoint(cache)

        // Similar shots: each photo against the one before it in time; a one-print cache makes it one print per photo.
        let chain = photos.compactMap { cache.records[$0.id] }.filter { !$0.isScreenshot }
        var last: (id: String, print: FeaturePrintObservation)?
        var unsupported = false // the request itself failed (the simulator): don't retry it for every photo this scan
        func featurePrint(_ r: AssetRecord) async -> FeaturePrintObservation? {
            if let last, last.id == r.id { return last.print }
            guard !unsupported, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [r.id], options: nil).firstObject,
                  let image = await thumbnail(asset, side: analysisSide) else { return nil }
            guard let p = try? await GenerateImageFeaturePrintRequest().perform(on: image) else { unsupported = true; return nil }
            last = (r.id, p)
            return p
        }
        started = Date()
        await SimilarShots.link(chain, distance: { a, b in
            if let pa = await featurePrint(a), let pb = await featurePrint(b) { return try? pa.distance(to: pb) }
            #if DEBUG
            if standIns { return await standInDistance(a, b) }
            #endif
            return nil
        }, update: { r, i in
            cache.records[r.id] = r
            if Date().timeIntervalSince(lastSave) > LibraryScanner.checkpointInterval {
                await progress(LibraryScanner.progressText("Finding similar shots", i, chain.count, since: started), Double(i) / Double(chain.count))
                await checkpoint(cache)
                lastSave = Date()
            }
        })
        await checkpoint(cache)
    }

    #if targetEnvironment(simulator)
    // shortcut: the simulator's text recognition crashed (EXC_BAD_ACCESS in TextRecognition) with 4 at once; the iPhone hasn't. One at a time there.
    static let parallel = 1
    #else
    static let parallel = 4
    #endif

    /// `r` with its analysis filled in, or nil when its thumbnail isn't on the device.
    static func analysed(_ r: AssetRecord, aesthetics: Bool) async -> AssetRecord? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [r.id], options: nil).firstObject,
              let image = await thumbnail(asset, side: analysisSide) else { return nil }
        var r = r
        await analyse(&r, image: image, asset: asset, aesthetics: aesthetics)
        return r
    }

    /// Fills in whatever `r` is missing from one thumbnail (plus a 1024 px one for the sensitive check's text).
    static func analyse(_ r: inout AssetRecord, image: CGImage, asset: PHAsset, aesthetics: Bool) async {
        if r.sharpness == nil {
            let faces = (try? await DetectFaceCaptureQualityRequest().perform(on: image)) ?? []
            r.faceQuality = faces.compactMap { $0.captureQuality?.score }.max() // a closure, not a key path: the setter is iOS 27+ only
            let boxes = faces.map { $0.boundingBox.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft) }
            (r.sharpness, r.brightness) = measure(image, faces: boxes)
            if #available(iOS 26.0, *) { r.smudge = (try? await DetectLensSmudgeRequest().perform(on: image))?.confidence }
        }
        if aesthetics, r.score == nil, let a = await aestheticsScore(image) {
            r.score = a.score
            r.isUtility = a.utility
        }
        if r.sensitive == nil {
            // Only candidates get the (slower) text check. Without aesthetics (simulator) every photo is a candidate.
            var candidate = !aesthetics || isLowScore(r) || r.isScreenshot
            if !candidate { candidate = ((try? await DetectDocumentSegmentationRequest().perform(on: image)) ?? nil) != nil }
            if candidate {
                guard let big = await thumbnail(asset, side: textSide) else { return } // retried next scan
                r.sensitive = await sensitiveReason(big) // nil (retried next scan) if text recognition failed
            } else {
                r.sensitive = ""
            }
        }
    }

    /// Why `image` looks sensitive (text rules, ID barcodes, or a document with a face on it), "" if nothing, or nil if
    /// text recognition failed. Barcodes and faces are extra votes, skipped where they can't run (the simulator).
    static func sensitiveReason(_ image: CGImage) async -> String? {
        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false // keeps MRZ lines and numbers as printed
        guard let observations = try? await text.perform(on: image) else { return nil }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let codes = (try? await DetectBarcodesRequest().perform(on: image)) ?? []
        let idBarcode = codes.contains { [.pdf417, .microPDF417, .aztec].contains($0.symbology) } // licences, ID cards, boarding passes
        if let why = SensitiveRules.reason(lines: lines, barcodes: codes.compactMap(\.payloadString), idBarcode: idBarcode) { return why }
        // A document with one small face printed on it: an ID card or a passport's photo page. Walls, posters and shop fronts
        // also segment as documents, so the quad must be confident, ID-shaped (ID-1 1.59, passport page 1.42), not the whole
        // frame, carry text, and hold exactly one face (on the author's library: 78 false alarms to 0, both real IDs kept).
        guard let doc = (try? await DetectDocumentSegmentationRequest().perform(on: image)) ?? nil, doc.confidence >= 0.7 else { return "" }
        let corners = [doc.topLeft, doc.topRight, doc.bottomRight, doc.bottomLeft].map(\.cgPoint)
        let box = CGRect(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!, width: 0, height: 0)
            .union(CGRect(origin: CGPoint(x: corners.map(\.x).max()!, y: corners.map(\.y).max()!), size: .zero))
        func side(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot((a.x - b.x) * CGFloat(image.width), (a.y - b.y) * CGFloat(image.height)) }
        let w = side(corners[0], corners[1]) + side(corners[3], corners[2]), h = side(corners[0], corners[3]) + side(corners[1], corners[2])
        let textOnCard = observations.filter { box.contains(CGPoint(x: $0.boundingBox.cgRect.midX, y: $0.boundingBox.cgRect.midY)) }.count
        guard (1.3...1.7).contains(max(w, h) / max(1, min(w, h))), box.width * box.height < 0.95, textOnCard >= 3 else { return "" }
        let faces = ((try? await DetectFaceRectanglesRequest().perform(on: image)) ?? []).map { $0.boundingBox.cgRect } // a closure: the key path needs an iOS 27+ setter
            .filter { box.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        return faces.count == 1 && faces[0].width * faces[0].height < 0.25 * box.width * box.height ? "ID with photo" : ""
    }

    /// Sharpness and brightness on a grey copy scaled to fit 512 px, so thumbnails of any size compare. Sharpness is the
    /// variance of the Laplacian inside each face box (normalised, top-left origin; faces under 24 px are ignored), or else
    /// in each tile of a 3×3 grid, whichever region is sharpest: a sharp subject on a soft (bokeh) background passes.
    static func measure(_ image: CGImage, faces: [CGRect] = []) -> (sharpness: Double, brightness: Double) {
        let (p, w, h) = ClipTools.grey(image, maxSide: 512)
        let brightness = Double(p.reduce(0) { $0 + Int($1) }) / Double(max(1, p.count)) / 255
        let size = CGSize(width: w, height: h)
        var regions = faces.map { CGRect(x: $0.minX * size.width, y: $0.minY * size.height, width: $0.width * size.width, height: $0.height * size.height) }
            .filter { $0.width >= 24 && $0.height >= 24 }
        if regions.isEmpty {
            regions = (0..<9).map { CGRect(x: CGFloat($0 % 3) * size.width / 3, y: CGFloat($0 / 3) * size.height / 3, width: size.width / 3, height: size.height / 3) }
        }
        return (regions.map { laplacianVariance(p, w, h, $0) }.max() ?? 0, brightness)
    }

    private static func laplacianVariance(_ p: [UInt8], _ w: Int, _ h: Int, _ r: CGRect) -> Double {
        let x0 = max(1, Int(r.minX)), x1 = min(w - 1, Int(r.maxX)), y0 = max(1, Int(r.minY)), y1 = min(h - 1, Int(r.maxY))
        guard x1 > x0, y1 > y0 else { return 0 }
        var sum = 0.0, sumSq = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * w + x
                let l = Double(p[i - 1]) + Double(p[i + 1]) + Double(p[i - w]) + Double(p[i + w]) - 4 * Double(p[i])
                sum += l
                sumSq += l * l
            }
        }
        let n = Double((x1 - x0) * (y1 - y0))
        return sumSq / n - (sum / n) * (sum / n)
    }

    /// Vision's aesthetics score and utility flag, or nil where the request can't run (the simulator).
    static func aestheticsScore(_ image: CGImage) async -> (score: Float, utility: Bool)? {
        if let o = try? await CalculateImageAestheticsScoresRequest().perform(on: image) { return (o.overallScore, o.isUtility) }
        #if DEBUG
        if standIns { return (-0.5, false) }
        #endif
        return nil
    }

    #if DEBUG
    /// The UI walkthrough's stand-ins for what the simulator can't run (aesthetics, feature prints). Debug builds only.
    static let standIns = ProcessInfo.processInfo.arguments.contains("-UnhoardSimulatorStandIns")

    /// Mean grey difference of 16 px copies, scaled so the same picture re-shot measures well under `distanceBelow`.
    static func standInDistance(_ a: AssetRecord, _ b: AssetRecord) async -> Double? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [a.id, b.id], options: nil)
        guard assets.count == 2, let ia = await thumbnail(assets[0], side: 64), let ib = await thumbnail(assets[1], side: 64) else { return nil }
        let ga = ClipTools.grey(ia, maxSide: 16).pixels, gb = ClipTools.grey(ib, maxSide: 16).pixels
        guard ga.count == gb.count else { return 1 }
        return zip(ga, gb).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(ga.count) / 255 * 4
    }
    #endif

    /// A small picture to find out whether the aesthetics request runs here.
    private static let probe: CGImage = {
        let cg = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        cg.setFillColor(UIColor.systemTeal.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return cg.makeImage()!
    }()

    /// The asset's local thumbnail, upright, about `side` px; never downloads (a smaller local one if that's all there is).
    static func thumbnail(_ asset: PHAsset, side: CGFloat) async -> CGImage? {
        if let image = await localImage(asset, side: side, mode: .highQualityFormat) { return image }
        return await localImage(asset, side: side, mode: .fastFormat)
    }

    private static func localImage(_ asset: PHAsset, side: CGFloat, mode: PHImageRequestOptionsDeliveryMode) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = mode // both call back once
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options) { image, _ in
                cont.resume(returning: image.flatMap(upright))
            }
        }
    }

    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }.cgImage
    }
}

/// Text rules for the sensitive check, on OCR lines and barcode payloads. Recall matters more than precision: a false
/// alarm only means an item is never bulk-selected.
enum SensitiveRules {
    private static let words = try! Regex(#"(?i)\b(passport|passeport|reisepass|licen[cs]e|visa|boarding pass|pass|date of birth|birth date|prescription|password|passcode|wi-?fi|identity|id card|identification|national id|residence permit|work permit|permanent resident|social security|insurance|medical|patient|signature|card number|cardholder|valid thru)\b"#)
    private static let acronyms = try! Regex(#"\b(DOB|D\.O\.B|FIN|NRIC|SSID|WPA2?|WPA3|PSK|CVV|CVC|IBAN|MRN|NHS|SSN|Rx)\b"#)

    static func reason(lines: [String], barcodes: [String] = [], idBarcode: Bool = false) -> String? {
        for line in lines + barcodes where isMRZ(line) { return "Passport or ID" }
        if barcodes.contains(where: { $0.uppercased().hasPrefix("WIFI:") }) { return "Wi-Fi password" }
        if barcodes.contains(where: { $0.firstMatch(of: #/^M[1-4][A-Z]/#) != nil }) { return "Boarding pass" }
        if idBarcode { return "ID or pass barcode" }
        let text = (lines + barcodes).joined(separator: "\n")
        for m in text.matches(of: #/\b(?:\d[ -]?){12,18}\d\b/#) {
            let digits = m.output.compactMap(\.wholeNumberValue)
            if Set(digits).count > 1, luhn(digits) { return "Card number" }
        }
        for m in text.uppercased().matches(of: #/\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{1,4})+/#) {
            // The match may run into the next word; try it whole, then without trailing groups.
            var groups = m.output.split(separator: " ").map(String.init)
            while groups.joined().count >= 15 {
                if isIBAN(groups.joined()) { return "Bank account (IBAN)" }
                groups.removeLast()
            }
        }
        if let k = text.firstMatch(of: words) ?? text.firstMatch(of: acronyms) { return "Mentions “\(text[k.range])”" }
        return nil
    }

    /// A passport or ID machine-readable line: 25+ of A–Z, 0–9 and '<', with '<<' in it ('«' is how OCR often reads '<<').
    static func isMRZ(_ line: String) -> Bool {
        let s = line.uppercased().replacingOccurrences(of: "«", with: "<<").filter { !$0.isWhitespace }
        return s.count >= 25 && s.contains("<<") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "<") }
    }

    static func luhn(_ digits: [Int]) -> Bool {
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, e in
            let d = e.offset % 2 == 1 ? e.element * 2 : e.element
            return total + (d > 9 ? d - 9 : d)
        }
        return sum % 10 == 0
    }

    /// ISO 13616: move the first four characters to the end, letters to 10–35, and the number mod 97 must be 1.
    static func isIBAN(_ s: String) -> Bool {
        guard (15...34).contains(s.count), s.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return false }
        var rest = 0
        for c in s.dropFirst(4) + s.prefix(4) {
            let v = c.wholeNumberValue ?? Int(c.asciiValue! - 55)
            rest = (rest * (v > 9 ? 100 : 10) + v) % 97
        }
        return rest == 1
    }
}

/// Similar shots: photos taken within a couple of minutes that look alike, chained photo to photo in time order.
/// Exact duplicates and bursts are left to Apple Photos.
enum SimilarShots {
    /// At most this long after the previous photo.
    static let within: TimeInterval = 120
    /// Feature-print distance below this looks alike. Calibrated on a real 6,900-photo library (512 px, pairs ≤ 120 s apart):
    /// below 0.10 nearly every pair is a re-take of one shot, 0.10–0.15 most, 0.15–0.20 about half, above 0.20 mostly a
    /// different pose, person or framing at the same spot. 0.35 (from sample pictures) linked 46% of that library.
    static let distanceBelow = 0.15

    /// Brings each photo's link to the one before it (in `photos`, oldest first) up to date; only stale links are redone.
    /// `distance` is nil when a thumbnail isn't on the device (that link is retried next scan).
    static func link(_ photos: [AssetRecord], distance: (AssetRecord, AssetRecord) async -> Double?,
                     update: (AssetRecord, Int) async -> Void) async {
        for (i, record) in photos.enumerated() {
            if Task.isCancelled { return }
            let prev = i > 0 ? photos[i - 1] : nil
            guard record.similarPrev != (prev?.id ?? "") else { continue }
            var r = record
            if let prev, let a = prev.created, let b = r.created, b.timeIntervalSince(a) <= within {
                guard let d = await distance(prev, r) else { continue }
                r.similarToPrev = d < distanceBelow
            } else {
                r.similarToPrev = false
            }
            r.similarPrev = prev?.id ?? ""
            await update(r, i)
        }
    }

    /// Groups of 2+ linked photos, newest group first, each with its best pick first and the rest oldest first.
    static func groups(_ records: some Collection<AssetRecord>) -> [[AssetRecord]] {
        let photos = records.filter { $0.isPhoto && !$0.isScreenshot }
            .sorted { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        var root: [String: String] = [:]
        var members: [String: [AssetRecord]] = [:]
        for r in photos { // a link always points back in time, so its target already has a root
            let id = r.similarToPrev == true ? r.similarPrev.flatMap { root[$0] } ?? r.id : r.id
            root[r.id] = id
            members[id, default: []].append(r)
        }
        return members.values.filter { $0.count > 1 }
            .map { g in
                let best = g.reduce(g[0]) { isBetter($1, $0) ? $1 : $0 }
                return [best] + g.filter { $0.id != best.id }
            }
            .sorted { (start($0), $0[0].id) > (start($1), $1[0].id) }
    }

    private static func start(_ group: [AssetRecord]) -> Date { group.map { $0.created ?? .distantPast }.min() ?? .distantPast }

    /// The best pick: a favourite, then (when both have faces) better face capture quality, then clearly sharper,
    /// then a higher aesthetics score.
    static func isBetter(_ a: AssetRecord, _ b: AssetRecord) -> Bool {
        if a.isFavorite != b.isFavorite { return a.isFavorite }
        if let fa = a.faceQuality, let fb = b.faceQuality, abs(fa - fb) >= 0.05 { return fa > fb }
        let sa = a.sharpness ?? 0, sb = b.sharpness ?? 0
        if max(sa, sb) > 0, abs(sa - sb) / max(sa, sb) >= 0.15 { return sa > sb }
        return (a.score ?? -2) > (b.score ?? -2)
    }
}
