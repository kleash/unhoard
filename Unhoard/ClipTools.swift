import AVFoundation
import Photos
import UniformTypeIdentifiers

/// Short-clip analysis (accident check, sharpest frame) and Clip → Still.
enum ClipTools {
    struct Luma: Equatable {
        var mean: Double // 0...1
        var variance: Double
    }

    /// The asset's video, from iCloud if needed. `fast` asks for a small rendition (enough for the accident check).
    static func avAsset(_ asset: PHAsset, fast: Bool) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = fast ? .fastFormat : .highQualityFormat
        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, info in
                if let video { cont.resume(returning: video) } else {
                    cont.resume(throwing: info?[PHImageErrorKey] as? Error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    /// `count` frames spread evenly over the clip, upright (track transform applied), at most `maxSide` px (0 = full size).
    static func frames(_ video: AVAsset, count: Int, maxSide: CGFloat) async throws -> [CGImage] {
        let duration = try await video.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: video)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var out: [CGImage] = []
        for i in 0..<count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            out.append(try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image)
        }
        return out
    }

    /// 8-bit grey pixels of `image` scaled to fit `maxSide`.
    static func grey(_ image: CGImage, maxSide: Int) -> (pixels: [UInt8], width: Int, height: Int) {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let cg = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        cg.interpolationQuality = .medium
        cg.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (pixels, w, h)
    }

    /// Mean and variance of luma on a 32 px downscale.
    static func luma(_ image: CGImage) -> Luma {
        let p = grey(image, maxSide: 32).pixels.map { Double($0) / 255 }
        let mean = p.reduce(0, +) / Double(p.count)
        return Luma(mean: mean, variance: p.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(p.count))
    }

    /// An obvious accident: every frame is very dark (or black), or nearly one flat colour (lens covered, in a pocket).
    static func isAccident(_ frames: [Luma]) -> Bool {
        !frames.isEmpty && frames.allSatisfy { $0.mean < 0.12 || $0.variance < 0.03 * 0.03 }
    }

    static func isAccident(_ video: AVAsset) async throws -> Bool {
        isAccident(try await frames(video, count: 3, maxSide: 64).map(luma))
    }

    /// Variance of the 4-neighbour Laplacian on a 512 px grey downscale: higher is sharper.
    static func sharpness(_ image: CGImage) -> Double {
        let (p, w, h) = grey(image, maxSide: 512)
        guard w > 2, h > 2 else { return 0 }
        var sum = 0.0, sumSq = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let l = Double(p[i - 1]) + Double(p[i + 1]) + Double(p[i - w]) + Double(p[i + w]) - 4 * Double(p[i])
                sum += l
                sumSq += l * l
            }
        }
        let n = Double((w - 2) * (h - 2))
        return sumSq / n - (sum / n) * (sum / n)
    }

    /// The sharpest of 5 full-resolution, upright frames.
    static func sharpestFrame(_ video: AVAsset) async throws -> CGImage {
        let frames = try await frames(video, count: 5, maxSide: 0)
        return frames.map { ($0, sharpness($0)) }.max { $0.1 < $1.1 }!.0
    }

    /// Saves `image` as a new photo dated and placed like the clip it came from; its local identifier.
    static func saveStill(_ image: CGImage, created: Date?, location: CLLocation?) async throws -> String {
        let data = NSMutableData()
        let heic = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil)
        let dest = heic ?? CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        var id: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data as Data, options: nil)
            request.creationDate = created
            request.location = location
            id = request.placeholderForCreatedAsset?.localIdentifier
        }
        return id ?? ""
    }

    /// Clip → Still: saves the clip's sharpest frame as a photo. The caller puts the clip in the tray.
    static func makeStill(fromClip id: String) async throws {
        guard let clip = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { throw CocoaError(.fileNoSuchFile) }
        let image = try await sharpestFrame(try await avAsset(clip, fast: false))
        _ = try await saveStill(image, created: clip.creationDate, location: clip.location)
    }
}
