import AVFoundation
import AVKit
import Photos
import SwiftUI

/// A full-screen look at one item: photos fit the screen, videos play with controls.
struct AssetPreview: View {
    let record: AssetRecord
    @Environment(DeleteTray.self) private var tray
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let inTray = tray.contains(record.id)
        NavigationStack {
            AssetMediaView(record: record, controls: true)
                .ignoresSafeArea(edges: .bottom)
                .background(.black)
                .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("closePreview")
                    }
                    ToolbarItem(placement: .principal) { MemoryLabel(record: record) }
                    ToolbarItemGroup(placement: .bottomBar) {
                        if record.isShortClip { MakeStillButton(record: record) { dismiss() } }
                        if record.isSensitive { HideButton(record: record) { dismiss() } }
                        Spacer()
                        Button(inTray ? "Keep" : "Add to Delete Tray", systemImage: inTray ? "arrow.uturn.backward" : "trash") {
                            tray.toggle(record.id)
                        }
                    }
                }
                .gesture(DragGesture().onEnded { if $0.translation.height > 120 { dismiss() } })
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
    @Environment(CleanerLibrary.self) private var library
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let player {
                    if controls { VideoPlayer(player: player) } else { PlayerLayerView(player: player) }
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit()
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
                    for await next in Thumbnails.images(library.images, asset, size: size, mode: .aspectFit) { image = next }
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
