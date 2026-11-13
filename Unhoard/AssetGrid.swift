import Photos
import SwiftUI
import UIKit

struct CategoryGridView: View {
    let category: CleanupCategory
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray
    @State private var swiping = false
    @State private var comparing: CompareGroup?
    @State private var asking: [[[AssetRecord]]]? // Similar batches waiting for consent
    @State private var settings = false
    @State private var waiting: [[AssetRecord]]? // groups to ask Claude about once a key is saved

    var body: some View {
        let items = library.sections[category] ?? []
        let groups = category == .similar ? tray.keeperFirst(SimilarShots.groups(items)) : nil
        let selectable = DeleteTray.selectable(items, groups: groups)
        let allSelected = !selectable.isEmpty && selectable.allSatisfy(tray.contains)
        let best = Set((groups ?? []).map { $0[0].id })
        Group {
            if category == .utility && library.aestheticsUnsupported {
                ContentUnavailableView("Needs an iPhone", systemImage: "iphone",
                                       description: Text("Utility shots are found with Apple's photo-quality check, which runs only on a real iPhone."))
                    .accessibilityIdentifier("needsIPhone")
            } else if items.isEmpty {
                ContentUnavailableView(library.status == nil ? "Nothing here" : "Still scanning…", systemImage: category.symbol,
                                       description: Text(category.blurb))
            } else {
                AssetGrid(items: items, groups: groups, caption: { category.caption($0) ?? (best.contains($0.id) ? "Best" : nil) },
                          compare: groups == nil ? nil : { comparing = CompareGroup(items: $0) },
                          askClaude: groups == nil ? nil : { ask([$0]) }) {
                    header(items)
                }
            }
        }
        .background { CleanerBackdrop(tint: category.tint) }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if category == .utility && !library.aestheticsUnsupported { SecondOpinionButton(items: items) }
                if let groups {
                    if let run = library.similarRun {
                        Menu {
                            Button("Stop Asking Claude", systemImage: "stop.fill", role: .destructive) { library.stopAskingClaude() }
                        } label: { Text("Claude \(run.done)/\(run.total) groups").monospacedDigit() }
                        .accessibilityIdentifier("similarClaudeProgress")
                    } else {
                        Button("Ask Claude about all groups (optional)…", systemImage: "sparkles") { ask(groups.filter { $0.allSatisfy { $0.similarLabel == nil } }) }
                            .disabled(library.isScanning || groups.isEmpty)
                            .accessibilityIdentifier("askClaudeAllGroups")
                    }
                }
                Button("Swipe", systemImage: "rectangle.stack") { swiping = true }
                    .disabled(items.isEmpty)
                    .accessibilityIdentifier("swipeButton")
                Button(allSelected ? "Deselect All" : "Select All") {
                    allSelected ? tray.remove(items.map(\.id)) : tray.add(selectable)
                }
                .disabled(selectable.isEmpty)
                .accessibilityIdentifier("selectAllButton")
            }
        }
        .safeAreaInset(edge: .bottom) { DeleteButton(scope: Set(items.map(\.id))) }
        .onAppear { preselect(groups) }
        .onChange(of: items.count) { preselect(groups) }
        .fullScreenCover(isPresented: $swiping) {
            SwipeReviewView(items: tray.unswiped(items), tint: category.tint).environment(library).environment(tray)
        }
        .fullScreenCover(item: $comparing) {
            SimilarCompareView(group: $0.items).environment(library).environment(tray)
        }
        .sheet(isPresented: $settings, onDismiss: {
            if let groups = waiting, CleanerKeyStore.load() != nil { Task { try? await Task.sleep(for: .milliseconds(400)); ask(groups) } } // see SecondOpinionButton
            waiting = nil
        }) { SecondOpinionSettings(asking: waiting != nil) }
        .sheet(isPresented: Binding { asking != nil } set: { if !$0 { asking = nil } }) {
            if let asking { SecondOpinionConsentSheet(records: Array(asking[0].joined()), batches: asking).environment(library) }
        }
        .alert("Claude stopped", isPresented: Binding { category == .similar && library.similarError != nil } set: { if !$0 { library.similarError = nil } }) {
            Button("OK") {}
        } message: { Text(library.similarError ?? "") }
        .animation(.default, value: tray.count == 0)
    }

    /// Count and size in big numbers, and one line on what the category is.
    private func header(_ items: [AssetRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(items.count.formatted()).cleanerNumber()
                Text(items.count == 1 ? "item" : "items").font(.headline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(items.reduce(Int64(0)) { $0 + $1.bytes }.formatted(.byteCount(style: .file))).cleanerNumber(.title2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .combine)
            Text(category.blurb).font(.subheadline).foregroundStyle(.secondary)
            if category == .screenshots, let line = library.screenshotCountLine {
                ShareLink("Share your count", item: line).font(.subheadline.weight(.semibold)).accessibilityIdentifier("shareCount")
            }
            if category != .sensitive, items.contains(where: \.isGuarded) {
                Label("Favourites, edited items and album items have a badge and are never selected for you, not even by Select All. Tap one to add it.",
                      systemImage: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if category == .sensitive {
                Label("Never selected for you. Open one to hide it, or tap to add it to the tray.", systemImage: "eye.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(category.tint)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerGlass(tint: category.tint.opacity(0.15))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Similar groups to Claude: the key first if there's none, then the consent sheet.
    private func ask(_ groups: [[AssetRecord]]) {
        let batches = SecondOpinion.batches(groups)
        if CleanerKeyStore.load() == nil { waiting = groups; settings = true } else if !batches.isEmpty { asking = batches }
    }

    /// Similar shots: all but each group's keeper go to the tray (the memory guard still applies).
    private func preselect(_ groups: [[AssetRecord]]?) {
        if category.preselects, let groups { tray.preselect(groups.flatMap { $0.dropFirst() }) }
    }
}

/// A Similar group to compare, as a sheet item.
struct CompareGroup: Identifiable {
    let items: [AssetRecord]
    var id: String { items.first?.id ?? "" }
}

/// A Photos-style grid: tap toggles tray membership, long-press previews, a horizontal-first drag selects a range.
struct AssetGrid<Header: View>: View {
    let items: [AssetRecord]
    /// Shown as groups under a header (Similar shots), keeper first; a drag sweeps them in this on-screen order.
    var groups: [[AssetRecord]]?
    /// A short label on a thumbnail.
    var caption: (AssetRecord) -> String? = { _ in nil }
    /// Similar groups: opens the side-by-side compare view.
    var compare: (([AssetRecord]) -> Void)?
    /// Similar groups: asks Claude about this group (after consent).
    var askClaude: (([AssetRecord]) -> Void)?
    @ViewBuilder var header: Header
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray
    @Environment(\.displayScale) private var displayScale
    @State private var assets: [String: PHAsset] = [:]
    @State private var width: CGFloat = 0
    @State private var cached: Set<String> = [] // ids, not positions: items shrink after a delete
    @State private var drag: (start: Int, adds: Bool, ids: Set<String>)? // ids: what the sweep so far will add or remove
    @State private var frames = Frames()
    @State private var preview: AssetRecord?
    @AppStorage("gridColumns") private var columns = 4 // pinch to change, like Photos
    @State private var filter = TrayFilter.all

    enum TrayFilter: String, CaseIterable { case all = "All", selected = "Selected", notSelected = "Not Selected" }
    private func passes(_ r: AssetRecord) -> Bool { filter == .all || tray.contains(r.id) == (filter == .selected) }
    private var shown: [AssetRecord] { filter == .all ? items : items.filter(passes) }
    private var shownGroups: [[AssetRecord]]? { filter == .all ? groups : groups.map { $0.map { $0.filter(passes) }.filter { !$0.isEmpty } } }
    /// The cells in on-screen order: what a drag ranges over.
    private var order: [AssetRecord] { shownGroups?.flatMap { $0 } ?? shown }
    /// Changes whenever cells can move: their order, the column count or the grid's width.
    private var layoutKey: Int {
        var h = Hasher()
        h.combine(columns)
        h.combine(width)
        order.forEach { h.combine($0.id) }
        return h.finalize()
    }
    private let spacing: CGFloat = 2

    private var side: CGFloat { max(1, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)) }
    private var pixels: CGSize { CGSize(width: side * displayScale, height: side * displayScale) }

    var body: some View {
        ScrollView {
            header
            Picker("Show", selection: $filter) {
                ForEach(TrayFilter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .accessibilityIdentifier("trayFilter")
            let layout = layoutKey
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                if let groups = shownGroups {
                    let position = Dictionary(shown.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
                    ForEach(groups, id: \.[0].id) { group in
                        Section {
                            ForEach(group) { cell(position[$0.id] ?? 0, $0, layout) }
                        } header: {
                            HStack {
                                Text("\(group.count) similar · \(group[0].created?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("similarGroupHeader")
                                Spacer()
                                if let compare {
                                    Button("Compare", systemImage: "rectangle.split.2x1") { compare(group) }
                                        .font(.footnote.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .cleanerGlass(Capsule(), interactive: true)
                                        .accessibilityHint("Compares the shots side by side and lets you pick the keeper.")
                                        .accessibilityIdentifier("compareButton")
                                }
                                if let askClaude {
                                    Button("Ask Claude (optional)", systemImage: "sparkles") { askClaude(group) }
                                        .labelStyle(.iconOnly)
                                        .font(.footnote.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .cleanerGlass(Capsule(), interactive: true)
                                        .disabled(library.isScanning || library.similarRun != nil)
                                        .accessibilityHint("Shows the previews that would go to Claude, which marks each shot as keep or duplicate.")
                                        .accessibilityIdentifier("askClaudeGroup")
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }
                    }
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, record in cell(i, record, layout) }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .coordinateSpace(.named("grid"))
            .gesture(DragSelectGesture(changed: dragged))
        }
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            let next = value.magnification > 1.15 ? columns - 1 : value.magnification < 0.87 ? columns + 1 : columns
            withAnimation(.snappy) { columns = min(6, max(2, next)) }
        })
        .sensoryFeedback(.selection, trigger: tray.count)
        .sensoryFeedback(.selection, trigger: drag?.ids)
        .task(id: items.map(\.id)) {
            let ids = items.map(\.id)
            assets = await Task.detached {
                var out: [String: PHAsset] = [:]
                PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in out[a.localIdentifier] = a }
                return out
            }.value
            cache(around: 0)
        }
        .onDisappear { library.images.stopCachingImagesForAllAssets() }
        .fullScreenCover(item: $preview) { AssetPreview(records: shown, start: $0).environment(library).environment(tray) }
    }

    private func cell(_ i: Int, _ record: AssetRecord, _ layout: Int) -> some View {
        AssetThumbnail(record: record, asset: assets[record.id], pixels: pixels, selected: isSelected(record), caption: caption(record))
            .frame(height: side)
            // Tagged with the layout: a layout change re-reports every live cell, and older frames stop counting.
            .onGeometryChange(for: Frames.Entry.self) { .init(layout: layout, rect: $0.frame(in: .named("grid"))) } action: { frames.byID[record.id] = $0 }
            .contentShape(Rectangle())
            .onTapGesture { tray.toggle(record.id) }
            .onLongPressGesture(minimumDuration: 0.25) { preview = record }
            .accessibilityAction(named: "Preview") { preview = record }
            .onAppear { if i % columns == 0 || groups != nil { cache(around: i) } }
    }

    private func isSelected(_ r: AssetRecord) -> Bool {
        if let drag, drag.ids.contains(r.id) { return drag.adds }
        return tray.contains(r.id)
    }

    /// The `order` index of the cell under a point in the grid; nil between cells or on a group header.
    private func index(at p: CGPoint, in order: [AssetRecord]) -> Int? {
        let layout = layoutKey
        guard let id = frames.byID.first(where: { $0.value.layout == layout && $0.value.rect.contains(p) })?.key else { return nil }
        return order.firstIndex { $0.id == id }
    }

    /// What sweeping `range` of `order` changes: adding never picks guarded memories, sensitive items or a group's keeper; tap them.
    private func sweep(_ order: [AssetRecord], _ range: ClosedRange<Int>, adds: Bool) -> Set<String> {
        let swept = Array(order[range.clamped(to: 0...max(0, order.count - 1))])
        return Set(adds ? DeleteTray.selectable(swept, groups: groups) : swept.map(\.id))
    }

    private func dragged(_ p: CGPoint, _ state: UIGestureRecognizer.State) {
        let order = order
        switch state {
        case .began:
            guard let i = index(at: p, in: order) else { return }
            let adds = !tray.contains(order[i].id)
            drag = (i, adds, sweep(order, i...i, adds: adds))
        case .changed:
            guard let d = drag, let i = index(at: p, in: order) else { return } // between cells: keep the range so far
            drag?.ids = sweep(order, min(d.start, i)...max(d.start, i), adds: d.adds)
        case .ended:
            guard let d = drag else { return }
            d.adds ? tray.add(d.ids) : tray.remove(d.ids)
            drag = nil
        default:
            drag = nil
        }
        // shortcut: no auto-scroll at the screen edge while dragging; lift, scroll and drag again. Add if users ask.
    }

    /// Pre-caches thumbnails a few screens around row-start `i` and lets go of the rest.
    private func cache(around i: Int) {
        guard !assets.isEmpty else { return }
        let lo = min(max(0, i - columns * 8), shown.count), hi = max(lo, min(shown.count, i + columns * 16))
        let old = cached, new = Set(shown[lo..<hi].map(\.id))
        func list(_ s: Set<String>) -> [PHAsset] { s.compactMap { assets[$0] } }
        library.images.stopCachingImages(for: list(old.subtracting(new)), targetSize: pixels, contentMode: .aspectFill, options: nil)
        library.images.startCachingImages(for: list(new.subtracting(old)), targetSize: pixels, contentMode: .aspectFill, options: nil)
        cached = new
    }
}

/// Cell frames by id, written as cells lay out; a class so frame updates don't redraw the grid while it scrolls.
/// Never removed when a cell scrolls off (its frame in the grid stays right until the layout changes).
private final class Frames {
    struct Entry: Equatable { var layout: Int; var rect: CGRect }
    var byID: [String: Entry] = [:]
}

extension AssetGrid where Header == EmptyView {
    init(items: [AssetRecord]) { self.init(items: items, header: { EmptyView() }) }
}

struct AssetThumbnail: View {
    let record: AssetRecord
    let asset: PHAsset?
    let pixels: CGSize
    let selected: Bool
    var caption: String?
    @Environment(CleanerLibrary.self) private var library
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .overlay { if selected { Color.black.opacity(0.25) } }
            .overlay(alignment: .bottomTrailing) {
                if record.isVideo {
                    VStack(alignment: .trailing, spacing: 0) {
                        if record.bytes > 0 { Text(record.bytes.formatted(.byteCount(style: .file))) }
                        Text(Duration.seconds(record.duration.rounded()).formatted(.time(pattern: .minuteSecond)))
                    }
                    .font(.caption2.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4)) // readable over bright frames
                    .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) { GuardBadge(record: record).padding(4) }
            .overlay(alignment: .topLeading) {
                if let caption, !caption.isEmpty {
                    Label(caption, systemImage: "crown.fill")
                        .labelStyle(CaptionLabelStyle(crown: caption == "Best"))
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(caption == "Best" ? AnyShapeStyle(Color.green) : AnyShapeStyle(.black.opacity(0.55)), in: Capsule())
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.title3)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.15), value: selected)
            .task(id: asset?.localIdentifier) {
                guard let asset else { return }
                for await next in Thumbnails.images(library.images, asset, size: pixels, mode: .aspectFill) { image = next }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([caption, record.spokenDescription].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(selected ? "In delete tray" : "")
            .accessibilityHint("Double-tap to add to or take out of the delete tray.")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("assetCell")
    }
}

/// A thumbnail caption, with a crown on the Best shot.
struct CaptionLabelStyle: LabelStyle {
    let crown: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            if crown { configuration.icon }
            configuration.title
        }
    }
}

/// The memory-guard badge: favourite, edited or in an album.
struct GuardBadge: View {
    let record: AssetRecord

    var body: some View {
        if let symbol = record.isFavorite ? "heart.fill" : record.hasAdjustments ? "wand.and.stars" : record.inUserAlbum ? "rectangle.stack.fill" : nil {
            Image(systemName: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.45), in: Circle())
                .accessibilityHidden(true)
        }
    }
}

extension AssetRecord {
    var spokenDescription: String {
        var parts = [isScreenRecording ? "Screen recording" : isScreenshot ? "Screenshot" : isVideo ? "Video" : "Photo"]
        if isVideo { parts.append(Duration.seconds(duration.rounded()).formatted(.units(width: .wide))) }
        if let created { parts.append(created.formatted(date: .abbreviated, time: .shortened)) }
        if isFavorite { parts.append("Favourite") }
        if hasAdjustments { parts.append("Edited") }
        if inUserAlbum { parts.append("In an album") }
        return parts.joined(separator: ", ")
    }
}

enum Thumbnails {
    /// The asset's image at `size`, a quick low-quality one first, then the final one. Cancelling the task cancels the request.
    static func images(_ manager: PHImageManager, _ asset: PHAsset, size: CGSize, mode: PHImageContentMode) -> AsyncStream<UIImage> {
        AsyncStream { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let id = manager.requestImage(for: asset, targetSize: size, contentMode: mode, options: options) { image, info in
                if let image { cont.yield(image) }
                if (info?[PHImageResultIsDegradedKey] as? Bool) != true { cont.finish() }
            }
            cont.onTermination = { _ in manager.cancelImageRequest(id) }
        }
    }
}

/// A pan that begins only when the finger first moves more sideways than up or down, so vertical drags still scroll.
struct DragSelectGesture: UIGestureRecognizerRepresentable {
    let changed: (CGPoint, UIGestureRecognizer.State) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        changed(context.converter.localLocation, pan.state)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        // The scroll view's own pan waits for this one to fail, so the two never fight.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
