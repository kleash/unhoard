import CoreImage
import ImageIO
import Photos
import XCTest
@testable import Tidyroll

final class SensitiveRulesTests: XCTestCase {
    func testPassportMRZ() {
        // OCR-like lines from a passport's data page, as Vision returns them (spaces, '«' for '<<').
        let page = ["PASSPORT", "United Kingdom of Great Britain", "P<GBRSMITH<<JOHN<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
                    "1234567897GBR8001014M2501017<<<<<<<<<<<<<<02"]
        XCTAssertEqual(SensitiveRules.reason(lines: page), "Passport or ID")
        XCTAssertTrue(SensitiveRules.isMRZ("I<SGPS1234567D«««««««««««««««"))
        XCTAssertTrue(SensitiveRules.isMRZ("P<USA DOE<<JANE <<<<<<<<<<<<<<<<<<<<<<<<"))
        XCTAssertFalse(SensitiveRules.isMRZ("<<< SALE >>>"))
        XCTAssertFalse(SensitiveRules.isMRZ("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"))
    }

    func testCardNumbersPassLuhn() {
        XCTAssertEqual(SensitiveRules.reason(lines: ["VISA", "4111 1111 1111 1111"]), "Card number")
        XCTAssertEqual(SensitiveRules.reason(lines: ["5500-0000-0000-0004  12/27"]), "Card number")
        XCTAssertEqual(SensitiveRules.reason(lines: ["378282246310005"]), "Card number") // Amex, 15 digits
        XCTAssertNil(SensitiveRules.reason(lines: ["4111 1111 1111 1112"]), "fails Luhn")
        XCTAssertNil(SensitiveRules.reason(lines: ["0000 0000 0000 0000"]), "all one digit")
        XCTAssertNil(SensitiveRules.reason(lines: ["Order 1234567890123 shipped"]), "13 digits failing Luhn")
        XCTAssertTrue(SensitiveRules.luhn([4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))
        XCTAssertFalse(SensitiveRules.luhn([4, 2]), "too short")
    }

    func testIBAN() {
        XCTAssertEqual(SensitiveRules.reason(lines: ["IBAN GB82 WEST 1234 5698 7654 32"]), "Bank account (IBAN)")
        XCTAssertEqual(SensitiveRules.reason(lines: ["de89370400440532013000 Sparkasse"]), "Bank account (IBAN)")
        XCTAssertEqual(SensitiveRules.reason(lines: ["Pay to GB82 WEST 1234 5698 7654 32 SORT 12-34-56"]), "Bank account (IBAN)", "trailing words")
        XCTAssertTrue(SensitiveRules.isIBAN("GB82WEST12345698765432"))
        XCTAssertFalse(SensitiveRules.isIBAN("GB82WEST12345698765433"), "bad check digits")
        XCTAssertNil(SensitiveRules.reason(lines: ["Ref AB12 CDEF 3456 7890 12"]))
    }

    func testKeywordsAndLabels() {
        let cases: [([String], String)] = [
            (["Date of Birth 01 JAN 1980"], "Mentions “Date of Birth”"),
            (["DRIVING LICENCE", "4d. LIC NO"], "Mentions “LICENCE”"),
            (["Employment Pass", "FIN G1234567N"], "Mentions “Pass”"),
            (["Network: HomeNet", "SSID HomeNet"], "Mentions “SSID”"),
            (["WPA2 key: hunter22"], "Mentions “WPA2”"),
            (["Rx", "Amoxicillin 500mg"], "Mentions “Rx”"),
            (["Prescription for J. Smith"], "Mentions “Prescription”"),
            (["DOB 12/03/1990"], "Mentions “DOB”"),
            (["Medical card", "Member 0042"], "Mentions “Medical”"),
        ]
        for (lines, why) in cases { XCTAssertEqual(SensitiveRules.reason(lines: lines), why, lines.joined(separator: " / ")) }
        // Everyday junk stays out.
        for lines in [["TOTAL 23.40", "Thank you for shopping"], ["Passenger information"], ["Call 6591234567"],
                      ["IKEA KALLAX 77x147 cm", "Art. 802.758.87"], ["whiteboard: sprint goals"], ["fin de semaine"]] {
            XCTAssertNil(SensitiveRules.reason(lines: lines), lines.joined(separator: " / "))
        }
    }

    func testBarcodes() {
        XCTAssertEqual(SensitiveRules.reason(lines: [], barcodes: ["WIFI:T:WPA;S:Home;P:secret;;"]), "Wi-Fi password")
        XCTAssertEqual(SensitiveRules.reason(lines: [], barcodes: ["M1SMITH/JOHN          EABC123 SINLHRSQ 0322 123Y031A0001 100"]), "Boarding pass")
        XCTAssertEqual(SensitiveRules.reason(lines: [], barcodes: ["ANSI 636014..."], idBarcode: true), "ID or pass barcode")
        XCTAssertNil(SensitiveRules.reason(lines: [], barcodes: ["https://example.com/menu"]), "a plain QR code is junk, not sensitive")
    }
}

final class BlurTests: XCTestCase {
    private let context = CIContext()
    private let w: CGFloat = 512, h: CGFloat = 384

    private func cg(_ image: CIImage) -> CGImage { context.createCGImage(image, from: CGRect(x: 0, y: 0, width: w, height: h))! }

    /// Fine detail everywhere: noise over a gradient, like foliage or fabric.
    private var detailed: CIImage {
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.transformed(by: .init(scaleX: 2, y: 2))
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 0.6])
        return noise.settingAlphaOne(in: CGRect(x: 0, y: 0, width: w, height: h)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) // the generator's alpha is random too
    }

    private func blurred(_ image: CIImage, _ radius: Double = 5) -> CIImage {
        image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    private func record(_ image: CGImage, faces: [CGRect] = []) -> AssetRecord {
        var r = rec("x")
        (r.sharpness, r.brightness) = PhotoAnalysis.measure(image, faces: faces)
        return r
    }

    func testSharpIsNotBlurryAndBlurredIs() {
        let sharp = record(cg(detailed)), soft = record(cg(blurred(detailed)))
        XCTAssertGreaterThan(sharp.sharpness!, PhotoAnalysis.blurryBelow * 5)
        XCTAssertLessThan(soft.sharpness!, PhotoAnalysis.blurryBelow)
        XCTAssertFalse(PhotoAnalysis.isBlurry(sharp))
        XCTAssertTrue(PhotoAnalysis.isBlurry(soft))
    }

    func testBokehWithSharpSubjectPasses() {
        // Only the middle tile of the 3×3 grid is in focus; the rest is a soft background.
        let subject = CGRect(x: w / 3, y: h / 3, width: w / 3, height: h / 3)
        let bokeh = detailed.cropped(to: subject).composited(over: blurred(detailed, 8))
        XCTAssertFalse(PhotoAnalysis.isBlurry(record(cg(bokeh))))
    }

    func testFacesAreMeasuredInsideTheirBoxes() {
        // Sharp scene, but the face area (top left, in normalised top-left coordinates) is out of focus.
        let soft = CGRect(x: 0.05, y: 0.05, width: 0.3, height: 0.3), face = soft.insetBy(dx: 0.03, dy: 0.03) // the face inside the soft subject
        let ciSoft = CGRect(x: soft.minX * w, y: (1 - soft.maxY) * h, width: soft.width * w, height: soft.height * h) // Core Image: y up
        let image = cg(blurred(detailed, 6).cropped(to: ciSoft).composited(over: detailed))
        XCTAssertFalse(PhotoAnalysis.isBlurry(record(image)), "no faces: the sharp tiles count")
        XCTAssertTrue(PhotoAnalysis.isBlurry(record(image, faces: [face])), "the face is soft: blurry")
        XCTAssertFalse(PhotoAnalysis.isBlurry(record(image, faces: [CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3)])), "a sharp face")
    }

    func testDarkShotsAreNeverBlurry() {
        let dark = record(cg(blurred(detailed).applyingFilter("CIExposureAdjust", parameters: ["inputEV": -6])))
        XCTAssertLessThan(dark.brightness!, PhotoAnalysis.darkBelow)
        XCTAssertFalse(PhotoAnalysis.isBlurry(dark), "night noise and darkness aren't judged")
    }

    func testMeasureIsNormalisedForThumbnailSize() {
        let big = PhotoAnalysis.measure(cg(blurred(detailed))).sharpness
        let large = blurred(detailed).transformed(by: .init(scaleX: 2, y: 2))
        let twice = PhotoAnalysis.measure(context.createCGImage(large, from: large.extent)!).sharpness
        XCTAssertEqual(twice, big, accuracy: max(5, big * 0.5), "a 1024 px thumbnail measures like a 512 px one")
    }

    func testSmudgeIsASecondVote() {
        var r = rec("x")
        (r.sharpness, r.brightness) = (60, 0.5)
        XCTAssertFalse(PhotoAnalysis.isBlurry(r))
        r.smudge = 0.9
        XCTAssertTrue(PhotoAnalysis.isBlurry(r), "borderline sharpness plus a smudged lens")
        r.sharpness = 300
        XCTAssertFalse(PhotoAnalysis.isBlurry(r), "a sharp photo stays, smudge or not")
    }
}

final class SimilarTests: XCTestCase {
    private func photo(_ id: String, at t: TimeInterval, favorite: Bool = false, face: Float? = nil, sharpness: Double = 100, score: Float? = nil) -> AssetRecord {
        var r = rec(id, modified: t, favorite: favorite)
        r.faceQuality = face
        r.sharpness = sharpness
        r.score = score
        return r
    }

    /// Runs the real linking with synthetic feature vectors (Euclidean distance), returning the updated records.
    private func link(_ photos: [AssetRecord], _ vectors: [String: [Double]]) async -> (records: [AssetRecord], updates: Int) {
        var out = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        var updates = 0
        func euclid(_ a: AssetRecord, _ b: AssetRecord) -> Double? {
            let pairs = zip(vectors[a.id]!, vectors[b.id]!)
            return pairs.map { (x: Double, y: Double) -> Double in (x - y) * (x - y) }.reduce(0, +).squareRoot()
        }
        await SimilarShots.link(photos, distance: { euclid($0, $1) }, update: { r, _ in
            out[r.id] = r
            updates += 1
        })
        return (photos.map { out[$0.id]! }, updates)
    }

    func testTimeWindowAndDistanceMakeGroups() async {
        let photos = [photo("a", at: 0), photo("b", at: 30), photo("c", at: 100), // alike, each within 2 minutes of the last
                      photo("d", at: 1000),                                       // alike but much later
                      photo("e", at: 1010), photo("f", at: 1020)]                 // close in time, different picture
        let vectors: [String: [Double]] = ["a": [0, 0], "b": [0.1, 0], "c": [0.2, 0.1], "d": [0.2, 0.1], "e": [3, 0], "f": [3.1, 0.1]]
        let (linked, updates) = await link(photos, vectors)
        XCTAssertEqual(updates, 6)
        XCTAssertEqual(SimilarShots.groups(linked).map { Set($0.map(\.id)) }, [["e", "f"], ["a", "b", "c"]], "newest group first")

        // A second pass has nothing to do.
        let again = await link(linked, vectors)
        XCTAssertEqual(again.updates, 0)

        // Deleting the middle shot relinks only its successor, to the shot before it.
        let afterDelete = await link(linked.filter { $0.id != "b" }, vectors)
        XCTAssertEqual(afterDelete.updates, 1)
        XCTAssertEqual(SimilarShots.groups(afterDelete.records).map { Set($0.map(\.id)) }, [["e", "f"], ["a", "c"]])
    }

    func testThresholdBoundary() async {
        let photos = [photo("a", at: 0), photo("b", at: 10), photo("c", at: 20)]
        let d = SimilarShots.distanceBelow
        let (linked, _) = await link(photos, ["a": [0], "b": [d - 0.01], "c": [2 * d]])
        XCTAssertEqual(linked.map(\.similarToPrev), [false, true, false])
        XCTAssertEqual(linked.map(\.similarPrev), ["", "a", "b"])
    }

    func testScreenshotsAndVideosAreNotGrouped() {
        var shot = photo("s", at: 10)
        shot.subtypes = PHAssetMediaSubtype.photoScreenshot.rawValue
        shot.similarPrev = "a"
        shot.similarToPrev = true
        XCTAssertTrue(SimilarShots.groups([photo("a", at: 0), shot]).isEmpty)
    }

    func testBestPickOrder() {
        let plain = photo("plain", at: 0, sharpness: 500, score: 0.9)
        XCTAssertTrue(SimilarShots.isBetter(photo("fav", at: 0, favorite: true, sharpness: 10), plain), "a favourite wins")
        XCTAssertTrue(SimilarShots.isBetter(photo("eyes", at: 0, face: 0.8, sharpness: 100), photo("blink", at: 0, face: 0.3, sharpness: 500)),
                      "with faces, capture quality before sharpness")
        XCTAssertTrue(SimilarShots.isBetter(photo("sharp", at: 0, sharpness: 300, score: 0.1), photo("soft", at: 0, sharpness: 100, score: 0.9)),
                      "then sharpness")
        XCTAssertTrue(SimilarShots.isBetter(photo("pretty", at: 0, sharpness: 100, score: 0.6), photo("plain", at: 0, sharpness: 105, score: 0.2)),
                      "then the aesthetics score when sharpness is about even")

        var group = [photo("a", at: 0, sharpness: 100), photo("b", at: 1, sharpness: 400), photo("c", at: 2, sharpness: 200)]
        group[1].similarPrev = "a"; group[1].similarToPrev = true
        group[2].similarPrev = "b"; group[2].similarToPrev = true
        XCTAssertEqual(SimilarShots.groups(group).first?.map(\.id), ["b", "a", "c"], "best first, then oldest first")
        XCTAssertEqual(CleanupCategory.sections(group)[.similar]?.map(\.id), ["b", "a", "c"])
    }
}

final class CategoryTests: XCTestCase {
    func testUtilitySensitiveAndBlurryCategories() {
        var receipt = rec("receipt"); receipt.score = 0.1; receipt.isUtility = true; receipt.sensitive = ""
        var dull = rec("dull"); dull.score = -0.4; dull.isUtility = false; dull.sensitive = ""
        var nice = rec("nice"); nice.score = 0.7; nice.isUtility = false; nice.sensitive = ""
        var passport = rec("passport"); passport.score = -0.6; passport.isUtility = true; passport.sensitive = "Passport or ID"
        var shot = rec("shot", screenshot: true); shot.score = -0.9; shot.isUtility = true
        var soft = rec("soft"); soft.sharpness = 5; soft.brightness = 0.5
        var softer = rec("softer"); softer.sharpness = 2; softer.brightness = 0.5
        var night = rec("night"); night.sharpness = 2; night.brightness = 0.05
        var memory = rec("memory"); memory.score = -0.8; memory.isUtility = false; memory.aiLabel = "memory"
        let s = CleanupCategory.sections([receipt, dull, nice, passport, shot, soft, softer, night, memory])
        XCTAssertEqual(s[.utility]?.map(\.id), ["dull", "receipt", "memory"], "worst first; the AI's memories last; no screenshots or sensitive")
        XCTAssertEqual(s[.sensitive]?.map(\.id), ["passport"])
        XCTAssertEqual(s[.blurry]?.map(\.id), ["softer", "soft"], "worst first, night shots left out")
        XCTAssertEqual(CleanupCategory.utility.caption(memory), "Memory")
        XCTAssertEqual(CleanupCategory.sensitive.caption(passport), "Passport or ID")
    }
}

final class SecondOpinionTests: XCTestCase {
    private func picture(_ w: Int, _ h: Int) -> CGImage {
        let cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        cg.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return cg.makeImage()!
    }

    func testClaudeRequestBody() throws {
        var passport = rec("ID-PASSPORT/L0/001")
        passport.sensitive = "Passport or ID"
        let items = [(record: rec("ID-ONE/L0/001"), jpeg: SecondOpinion.jpeg(picture(4032, 3024))),
                     (record: passport, jpeg: SecondOpinion.jpeg(picture(800, 600))),
                     (record: rec("ID-TWO/L0/001"), jpeg: SecondOpinion.jpeg(picture(300, 900)))]
        let (request, sent) = try SecondOpinion.claudeRequest(items, apiKey: "sk-test")
        XCTAssertEqual(sent.map(\.id), ["ID-ONE/L0/001", "ID-TWO/L0/001"], "sensitive items are never sent")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")

        let raw = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertFalse(raw.contains("ID-"), "no library identifiers leave the device")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"], "thinking can't be disabled on this model, so it isn't sent")
        XCTAssertNil(body["temperature"])
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertEqual((output["format"] as? [String: Any])?["type"] as? String, "json_schema")

        let content = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first)?["content"] as? [[String: Any]])
        let texts = content.compactMap { $0["text"] as? String }
        XCTAssertTrue(texts.contains("Photo id 1:") && texts.contains("Photo id 2:") && !texts.contains("Photo id 3:"))
        let images = content.filter { $0["type"] as? String == "image" }
        XCTAssertEqual(images.count, 2)
        for block in images {
            let source = try XCTUnwrap(block["source"] as? [String: Any])
            XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
            let data = try XCTUnwrap(Data(base64Encoded: source["data"] as! String))
            let src = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
            let w = props[kCGImagePropertyPixelWidth] as! Int, h = props[kCGImagePropertyPixelHeight] as! Int
            XCTAssertLessThanOrEqual(max(w, h), 512)
            XCTAssertNil(props[kCGImagePropertyGPSDictionary], "no location")
            XCTAssertNil((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal], "no capture date")
            XCTAssertNil((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake], "no camera")
        }
    }

    func testParsesVerdictsFromCannedResponse() throws {
        let text = #"{"results":[{"id":"1","label":"memory","reason":"Friends at a night market."},{"id":"2","label":"utility","reason":"A shelf label."},{"id":"3","label":"cat","reason":"?"}]}"#
        let response: [String: Any] = ["type": "message", "stop_reason": "end_turn",
                                       "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]]]
        let verdicts = try SecondOpinion.parse(try JSONSerialization.data(withJSONObject: response), status: 200, apiKey: "k")
        XCTAssertEqual(verdicts, [.init(id: "1", label: "memory", reason: "Friends at a night market."),
                                  .init(id: "2", label: "utility", reason: "A shelf label.")], "unknown labels are dropped")
    }

    func testRefusalAndErrorsAreReported() throws {
        let refusal = try JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []] as [String: Any])
        XCTAssertThrowsError(try SecondOpinion.parse(refusal, status: 200, apiKey: "k")) {
            XCTAssertEqual($0.localizedDescription, "Claude declined to look at these photos")
        }
        XCTAssertThrowsError(try SecondOpinion.parse(Data(), status: 401, apiKey: "k")) {
            XCTAssertEqual($0.localizedDescription, "That API key was rejected")
        }
        let leaky = try JSONSerialization.data(withJSONObject: ["error": ["message": "bad key sk-secret"]])
        XCTAssertThrowsError(try SecondOpinion.parse(leaky, status: 400, apiKey: "sk-secret")) {
            XCTAssertEqual($0.localizedDescription, "bad key •••", "the key never shows in an error")
        }
    }

    func testAppleModelGating() {
        if #unavailable(iOS 27.0) {
            XCTAssertEqual(SecondOpinion.appleUnavailableReason, "Needs iOS 27")
        } else {
            // On iOS 27 it depends on the device; it must answer without crashing.
            _ = SecondOpinion.appleUnavailableReason
        }
    }
}
