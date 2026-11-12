import AVFoundation
import AVKit
import Photos
import SwiftUI

/// A full-screen look at items, swipe left/right for the next: photos fit the screen, videos play with controls.
struct AssetPreview: View {
    let records: [AssetRecord]
    @State private var current: String
    @State private var zoomed = false
    @Environment(DeleteTray.self) private var tray
    @Environment(\.dismiss) private var dismiss

    init(records: [AssetRecord], start: AssetRecord) {
        self.records = records.contains { $0.id == start.id } ? records : [start]
        _current = State(initialValue: start.id)
    }

    private var record: AssetRecord { records.first { $0.id == current } ?? records[0] }

    var body: some View {
        let record = record
        let inTray = tray.contains(record.id)
        NavigationStack {
            TabView(selection: $current) {
                ForEach(records) { r in
                    // Only the shown page loads a video, so neighbours don't play sound off-screen.
                    Group { if r.id == current || !r.isVideo { AssetMediaView(record: r, controls: true, zoomed: r.id == current ? $zoomed : nil) } else { Color.black } }
                        .tag(r.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: current) { zoomed = false }
                .ignoresSafeArea(edges: .bottom)
                .background(.black)
                .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("closePreview")
                    }
                    ToolbarItem(placement: .principal) { MemoryLabel(record: record).accessibilityElement(children: .combine).accessibilityIdentifier("preview-\(record.id)") }
                    ToolbarItemGroup(placement: .bottomBar) {
                        if record.isShortClip { MakeStillButton(record: record) { dismiss() } }
                        if record.isSensitive { HideButton(record: record) { dismiss() } }
                        Spacer()
                        Button(inTray ? "Keep" : "Add to Delete Tray", systemImage: inTray ? "arrow.uturn.backward" : "trash") {
                            tray.toggle(record.id)
                        }
                    }
                }
                .simultaneousGesture(DragGesture().onEnded { if $0.translation.height > 120 { dismiss() } }, including: zoomed ? .none : .all) // simultaneous: paging needs the horizontal drags; off while zoomed so panning down doesn't close
        }
        .preferredColorScheme(.dark) // a media viewer, like Photos
        .sensoryFeedback(.selection, trigger: inTray)
    }
}

/// Date plus why an item is protected, under the title.
struct MemoryLabel: View {
    let record: AssetRecord

    var body: some View {
        VStack(spacing: 0) {
            Text(record.created?.formatted(date: .abbreviated, time: .shortened) ?? "").font(.headline)
            let reasons = [record.isFavorite ? "Favourite" : nil, record.hasAdjustments ? "Edited" : nil, record.inUserAlbum ? "In an album" : nil]
                .compactMap { $0 }
            if !reasons.isEmpty {
                Label(reasons.joined(separator: " · "), systemImage: "heart.fill").font(.caption).foregroundStyle(.pink)
            }
            if record.isSensitive {
                Label(record.sensitive ?? "", systemImage: "lock.shield").font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
            if let label = record.aiLabel {
                Text("\(label.capitalized): \(record.aiReason ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let label = record.similarLabel {
                Text("Claude: \(label): \(record.similarReason ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .labelStyle(.titleAndIcon) // a toolbar shows labels as icons only by default
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Clip → Still: saves the sharpest frame as a photo (same date and place) and puts the clip in the tray.
struct MakeStillButton: View {
    let record: AssetRecord
    var saved: () -> Void = {}
    @Environment(DeleteTray.self) private var tray
    @State private var working = false
    @State private var failure: String?
    @State private var success = 0

    var body: some View {
        Button {
            working = true
            Task {
                do {
                    try await ClipTools.makeStill(fromClip: record.id)
                    tray.add([record.id])
                    success += 1
                    saved()
                } catch {
                    failure = error.localizedDescription
                }
                working = false
            }
        } label: {
            if working { ProgressView() } else { Label("Make Still", systemImage: "camera.aperture").lineLimit(1).fixedSize() }
        }
        .disabled(working)
        .accessibilityHint("Saves the sharpest frame as a photo and puts the clip in the delete tray.")
        .accessibilityIdentifier("makeStillButton")
        .sensoryFeedback(.success, trigger: success)
        .alert("Couldn't make a still", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK") {}
        } message: { Text(failure ?? "") }
    }
}

/// Hide: moves the item to the Hidden album (Face ID-locked) and out of the cleaner and the tray.
struct HideButton: View {
    let record: AssetRecord
    var hidden: () -> Void = {}
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray
    @State private var failure: String?

    var body: some View {
        Button {
            Task {
                do {
                    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [record.id], options: nil).firstObject else { return }
                    try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest(for: asset).isHidden = true }
                    tray.remove([record.id])
                    library.remove([record.id])
                    hidden()
                } catch let error as PHPhotosError where error.code == .userCancelled {
                } catch {
                    failure = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 6) { Image(systemName: "eye.slash.fill"); Text("Hide") }.lineLimit(1).fixedSize() // a toolbar would show a Label's icon only
        }
        .cleanerProminent(.orange)
        .accessibilityHint("Moves it to the Hidden album, which Face ID locks.")
        .accessibilityIdentifier("hideButton")
        .alert("Couldn't hide it", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK") {}
        } message: { Text(failure ?? "") }
    }
}

/// A photo at screen size, or a video: with controls, or looping silently (for swiping).
struct AssetMediaView: View {
    let record: AssetRecord
    let controls: Bool
    var zoomed: Binding<Bool>? = nil // the preview's current page; other pages zoom back to fit
    @Environment(CleanerLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loading = false // a quick blurry version is showing; the full one (maybe from iCloud) is on its way

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player {
                    if controls { VideoPlayer(player: player) } else { PlayerLayerView(player: player) }
                } else if let image {
                    if controls { ZoomableImage(image: image, zoomed: zoomed) } else { Image(uiImage: image).resizable().scaledToFit() }
                    if loading {
                        ProgressView().controlSize(.large).tint(.white).padding(14).background(.black.opacity(0.45), in: Circle())
                            .allowsHitTesting(false)
                            .accessibilityLabel("Loading full quality")
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: record.id) {
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [record.id], options: nil).firstObject else { return }
                let size = CGSize(width: geo.size.width * displayScale, height: geo.size.height * displayScale)
                if record.isVideo, let item = await Self.playerItem(asset) {
                    let p = AVPlayer(playerItem: item)
                    p.isMuted = !controls
                    player = p
                    p.play()
                    // Loop: back to the start whenever it ends.
                    for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                        await p.seek(to: .zero)
                        p.play()
                    }
                } else {
                    loading = true
                    for await next in Thumbnails.images(library.images, asset, size: size, mode: .aspectFit) { image = next }
                    loading = false
                }
            }
            .onDisappear { player?.pause() }
        }
        .accessibilityElement(children: controls && record.isVideo ? .contain : .ignore)
        .accessibilityLabel(record.spokenDescription)
    }

    static func playerItem(_ asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in cont.resume(returning: item) }
        }
    }
}

/// A bare AVPlayerLayer (no controls to catch the swipe).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        (view.layer as! AVPlayerLayer).videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) { (view.layer as! AVPlayerLayer).player = player }
}

/// A photo you can pinch or double-tap to zoom and pan, like Photos (a UIScrollView nested in the pager).
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let zoomed: Binding<Bool>?

    func makeUIView(context: Context) -> ZoomView { ZoomView() }

    func updateUIView(_ view: ZoomView, context: Context) {
        if let zoomed { view.onZoom = { zoomed.wrappedValue = $0 } } else { view.fit() }
        if view.imageView.image !== image { view.imageView.image = image; view.setNeedsLayout() }
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()
        var onZoom: (Bool) -> Void = { _ in }
        private var zoomed = false

        init() {
            super.init(frame: .zero)
            delegate = self
            maximumZoomScale = 5
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            addSubview(imageView)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        /// Zoomed out: zoom in 2.5x on the tapped spot. Zoomed in: back to fit.
        @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
            if zoomed {
                setZoomScale(minimumZoomScale, animated: true)
            } else {
                let p = tap.location(in: imageView), scale: CGFloat = 2.5
                let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
                zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
            setZoomed(!zoomed)
        }

        override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === panGestureRecognizer else { return super.gestureRecognizerShouldBegin(g) }
            guard zoomed else { return false } // fit to screen: the drag belongs to the pager and swipe-down
            let v = panGestureRecognizer.velocity(in: self)
            guard abs(v.x) > abs(v.y) else { return true }
            // Already at the left/right edge: this sideways swipe goes to the pager (next/previous photo), like Photos.
            let minX = -contentInset.left, maxX = contentSize.width - bounds.width + contentInset.right
            return v.x > 0 ? contentOffset.x > minX + 1 : contentOffset.x < maxX - 1
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // At 1x the image fits the screen; zooming scales from there.
            if zoomScale == 1, let size = imageView.image?.size, size.width > 0, size.height > 0 {
                imageView.frame = CGRect(origin: .zero, size: AVMakeRect(aspectRatio: size, insideRect: bounds).size)
                contentSize = imageView.frame.size
            }
            center()
        }

        /// Keeps a smaller-than-screen image in the middle.
        private func center() {
            let x = max(0, (bounds.width - contentSize.width) / 2), y = max(0, (bounds.height - contentSize.height) / 2)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }
        // Zoomed from the moment a pinch starts, so the pinch itself can't count as a swipe-down that closes the preview.
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { setZoomed(true) }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { setZoomed(scale > minimumZoomScale + 0.01) }

        /// Swiped away from: back to fit, quietly (the preview has already reset its zoomed flag).
        func fit() {
            onZoom = { _ in }
            setZoomScale(minimumZoomScale, animated: false)
            zoomed = false
        }

        private func setZoomed(_ now: Bool) {
            if now != zoomed { zoomed = now; onZoom(now) }
        }
    }
}
