import AVFoundation
import CoreImage
import Photos
import XCTest
@testable import Tidyroll

final class ClipTests: XCTestCase {
    private let context = CIContext()

    private func cgImage(_ image: CIImage) -> CGImage { context.createCGImage(image, from: image.extent)! }

    private func solid(_ grey: CGFloat, _ w: CGFloat = 320, _ h: CGFloat = 240) -> CIImage {
        CIImage(color: CIColor(red: grey, green: grey, blue: grey)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// A scene-like picture: a bright diagonal gradient with a few dark bars.
    private func scene(_ w: CGFloat = 320, _ h: CGFloat = 240) -> CIImage {
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: w, y: h),
            "inputColor0": CIColor(red: 0.9, green: 0.7, blue: 0.3), "inputColor1": CIColor(red: 0.2, green: 0.4, blue: 0.8),
        ])!.outputImage!
        var out = gradient.cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        for x in stride(from: CGFloat(20), to: w, by: 80) {
            out = CIImage(color: .black).cropped(to: CGRect(x: x, y: 0, width: 16, height: h)).composited(over: out)
        }
        return out
    }

    private func checkerboard(_ w: CGFloat = 320, _ h: CGFloat = 240, square: CGFloat = 8) -> CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": square, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!
            .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    // MARK: Accident classifier

    func testLumaOfFlatAndBusyPictures() {
        let black = ClipTools.luma(cgImage(solid(0)))
        XCTAssertEqual(black.mean, 0, accuracy: 0.01)
        XCTAssertEqual(black.variance, 0, accuracy: 0.0001)
        let busy = ClipTools.luma(cgImage(checkerboard(square: 80))) // big squares survive the 32 px downscale
        XCTAssertEqual(busy.mean, 0.5, accuracy: 0.1)
        XCTAssertGreaterThan(busy.variance, 0.05)
    }

    func testAccidentClassifier() {
        let luma = { ClipTools.luma(self.cgImage($0)) }
        XCTAssertTrue(ClipTools.isAccident([luma(solid(0)), luma(solid(0.02)), luma(solid(0))]), "black")
        XCTAssertTrue(ClipTools.isAccident([luma(solid(0.45)), luma(solid(0.5)), luma(solid(0.45))]), "uniform, as in a pocket")
        XCTAssertTrue(ClipTools.isAccident([luma(scene().applyingFilter("CIExposureAdjust", parameters: ["inputEV": -5]))]), "very dark")
        XCTAssertFalse(ClipTools.isAccident([luma(scene()), luma(scene()), luma(scene())]), "normal")
        XCTAssertFalse(ClipTools.isAccident([luma(solid(0)), luma(scene()), luma(solid(0))]), "one good frame keeps it")
        XCTAssertFalse(ClipTools.isAccident([]))
    }

    func testAccidentOnRealClips() async throws {
        let dark = try await makeVideo(seconds: 2) { _ in self.solid(0.01) }
        let normal = try await makeVideo(seconds: 2) { _ in self.scene() }
        let accidentDark = try await ClipTools.isAccident(AVURLAsset(url: dark))
        let accidentNormal = try await ClipTools.isAccident(AVURLAsset(url: normal))
        XCTAssertTrue(accidentDark)
        XCTAssertFalse(accidentNormal)
    }

    // MARK: Sharpest frame

    func testSharpnessOrdersSharpOverBlurredOverFlat() {
        let sharp = ClipTools.sharpness(cgImage(checkerboard()))
        let blurred = ClipTools.sharpness(cgImage(checkerboard().clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 6])
                .cropped(to: checkerboard().extent)))
        let flat = ClipTools.sharpness(cgImage(solid(0.5)))
        XCTAssertGreaterThan(sharp, blurred * 4)
        XCTAssertGreaterThan(blurred, flat)
        XCTAssertEqual(flat, 0, accuracy: 0.01)
    }

    func testSharpestFramePicksTheSharpMoment() async throws {
        // 5 half-second segments; frames are sampled at the middle of each. Only the third is in focus.
        let blur = checkerboard().clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 6]).cropped(to: checkerboard().extent)
        let clip = try await makeVideo(seconds: 2.5) { t in (1.0..<1.5).contains(t) ? self.checkerboard() : blur }
        let frame = try await ClipTools.sharpestFrame(AVURLAsset(url: clip))
        XCTAssertEqual(frame.width, 320)
        XCTAssertGreaterThan(ClipTools.sharpness(frame), ClipTools.sharpness(cgImage(blur)) * 4)
    }

    // MARK: Orientation

    /// A portrait iPhone clip: landscape pixels plus a 90° track transform. Shown upright it is red top-left, green top-right,
    /// blue along the bottom; the still must look the same (the first build of Liveloom got this upside down).
    func testStillFromPortraitClipIsUpright() async throws {
        let w: CGFloat = 320, h: CGFloat = 240
        // Buffer (Core Image, y up): left half red, top-left quarter green, right half blue. The 90° transform maps
        // buffer left → display top and buffer top → display right.
        let buffer = CIImage(color: .green).cropped(to: CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
            .composited(over: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: w / 2, height: h)))
            .composited(over: CIImage(color: .blue).cropped(to: CGRect(x: w / 2, y: 0, width: w / 2, height: h)))
        let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0) // as an iPhone held upright writes it
        let clip = try await makeVideo(seconds: 1, transform: portrait) { _ in buffer }
        let still = try await ClipTools.sharpestFrame(AVURLAsset(url: clip))
        XCTAssertEqual(still.width, 240)
        XCTAssertEqual(still.height, 320)
        let px = rgb(still)
        func colour(_ x: Int, _ y: Int) -> [Int] { let i = (y * still.width + x) * 4; return [px[i], px[i + 1], px[i + 2]].map { $0 > 128 ? 1 : 0 } }
        XCTAssertEqual(colour(60, 60), [1, 0, 0], "top left is red")
        XCTAssertEqual(colour(180, 60), [0, 1, 0], "top right is green")
        XCTAssertEqual(colour(60, 260), [0, 0, 1], "bottom left is blue")
        XCTAssertEqual(colour(180, 260), [0, 0, 1], "bottom right is blue")
    }

    /// Saving the still keeps the clip's date and place. Needs full Photos access on the simulator (see README).
    func testSaveStillKeepsDateAndLocation() async throws {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw XCTSkip("Needs full Photos access for read-back (see README).")
        }
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let place = CLLocation(latitude: 51.5007, longitude: -0.1246)
        let id = try await ClipTools.saveStill(cgImage(scene()), created: date, location: place)
        let saved = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        XCTAssertEqual(saved.creationDate, date)
        XCTAssertEqual(saved.location?.coordinate.latitude ?? 0, 51.5007, accuracy: 0.0001)
        XCTAssertEqual(saved.location?.coordinate.longitude ?? 0, -0.1246, accuracy: 0.0001)
        XCTAssertEqual(saved.pixelWidth, 320)
    }

    // MARK: Helpers

    private func rgb(_ image: CGImage) -> [Int] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let cg = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data.map(Int.init)
    }

    /// A 320×240, 30 fps H.264 clip whose frame at time t is `picture(t)`, tagged with `transform`.
    private func makeVideo(seconds: Double, transform: CGAffineTransform = .identity, picture: @escaping (Double) -> CIImage) async throws -> URL {
        let size = CGSize(width: 320, height: 240), fps: Int32 = 30
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".mov")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * Double(fps))
        for f in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            context.render(picture(Double(f) / Double(fps)), to: buffer!, bounds: CGRect(origin: .zero, size: size),
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            XCTAssertTrue(adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: fps))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, "\(String(describing: writer.error))")
        return url
    }
}
