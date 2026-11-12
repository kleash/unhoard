import SwiftUI

/// A stack of cards, one item at a time: swipe left (or Delete) to put it in the tray, right (or Keep) to keep it; Undo steps back.
/// Keeps are remembered in the tray's file, so callers open the deck on `tray.unswiped(_:)` and kept items don't come back.
struct SwipeReviewView: View {
    /// Fixed when the deck opens: the caller's list changes as items go to the tray.
    @State private var items: [AssetRecord]
    var tint: Color = .indigo
    @Environment(DeleteTray.self) private var tray
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var history: [(index: Int, trayed: Bool)] = []
    @State private var offset: CGSize = .zero
    @State private var deciding = false // ignore taps and swipes while the card flies off
    @State private var armed = false // dragged past the point where letting go decides (a haptic when it changes)
    private let threshold: CGFloat = 120

    init(items: [AssetRecord], tint: Color = .indigo) {
        _items = State(initialValue: items)
        self.tint = tint
        #if DEBUG
        if CleanerDemo.has("DemoDrag") { _offset = State(initialValue: CGSize(width: -110, height: 12)) } // a mid-drag screenshot
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                stats
                if index < items.count {
                    ZStack {
                        ForEach(Array(items[index..<min(index + 3, items.count)].enumerated()), id: \.element.id) { depth, record in
                            card(record, depth: depth).zIndex(Double(-depth))
                        }
                    }
                    .frame(maxHeight: .infinity)
                    controls(items[index])
                } else {
                    ContentUnavailableView("All done", systemImage: "checkmark.circle",
                                           description: Text("You've been through every item. Review the tray with Delete."))
                        .symbolEffect(.bounce, value: index)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding()
            .background { CleanerBackdrop(tint: tint) }
            .navigationTitle(index < items.count ? "\(index + 1) of \(items.count)" : "Swipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("swipeDone") }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo).disabled(history.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { DeleteButton(scope: Set(items.map(\.id))) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: history.count)
        .sensoryFeedback(.selection, trigger: armed)
    }

    /// What this session put in the tray, and the current run of the same decision.
    private var stats: some View {
        let bytes = history.filter(\.trayed).reduce(Int64(0)) { $0 + items[$1.index].bytes }
        let streak = history.reversed().prefix { $0.trayed == history.last?.trayed }.count
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(bytes.formatted(.byteCount(style: .file, spellsOutZero: false))).cleanerNumber(.title)
                Text("cleared when you delete").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if streak >= 2, let trayed = history.last?.trayed {
                Label("\(streak) \(trayed ? "deletes" : "keeps") in a row", systemImage: "flame.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(trayed ? .red : .green)
                    .symbolEffect(.bounce, value: streak)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cleanerGlass(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: history.count)
    }

    private func card(_ record: AssetRecord, depth: Int) -> some View {
        let top = depth == 0
        let pull = min(1, abs(offset.width) / threshold) // the cards behind move up as the top one goes
        let step = CGFloat(depth) - pull
        let lean = offset.width / threshold
        return AssetMediaView(record: record, controls: false)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
            .overlay(alignment: .topLeading) { if top { stamp("KEEP", .green, angle: -14).opacity(Double(lean)) } }
            .overlay(alignment: .topTrailing) { if top { stamp("DELETE", .red, angle: 14).opacity(Double(-lean)) } }
            .overlay(alignment: .bottomLeading) { GuardBadge(record: record).scaleEffect(1.6).padding(18) }
            .shadow(color: .black.opacity(top ? 0.35 : 0.15), radius: top ? 18 : 8, y: 8)
            .scaleEffect(top ? 1 : 1 - 0.06 * step)
            .offset(y: top ? 0 : 18 * step)
            .opacity(depth == 2 ? Double(0.6 + 0.4 * pull) : 1)
            .offset(top ? offset : .zero)
            .rotationEffect(.degrees(top && !reduceMotion ? Double(offset.width) / 18 : 0), anchor: .bottom)
            .allowsHitTesting(top)
            .gesture(drag, including: top ? .all : .none)
            .accessibilityHidden(!top)
            .accessibilityAction(named: "Delete") { decide(trayed: true) }
            .accessibilityAction(named: "Keep") { decide(trayed: false) }
            .accessibilityIdentifier(top ? "swipeCard" : "")
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged {
                guard !deciding else { return }
                offset = $0.translation
                armed = abs(offset.width) > threshold
            }
            .onEnded { g in
                guard !deciding else { return }
                let push = g.predictedEndTranslation.width
                armed = false
                if push < -150 || g.translation.width < -threshold { decide(trayed: true) } else if push > 150 || g.translation.width > threshold { decide(trayed: false) } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.4)) { offset = .zero }
                }
            }
    }

    private func controls(_ record: AssetRecord) -> some View {
        HStack(spacing: 16) {
            roundButton("Delete", "xmark", .red) { decide(trayed: true) }.accessibilityIdentifier("swipeDelete")
            Spacer(minLength: 0)
            if record.isShortClip {
                MakeStillButton(record: record) { advance(trayed: true) }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .cleanerGlass(Capsule(), interactive: true)
            }
            if record.isSensitive {
                HideButton(record: record) { advance(trayed: false) }.controlSize(.large)
            }
            Spacer(minLength: 0)
            roundButton("Keep", "heart.fill", .green) { decide(trayed: false) }.accessibilityIdentifier("swipeKeep")
        }
    }

    private func roundButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.title.bold())
                .foregroundStyle(color)
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .cleanerGlass(Circle(), interactive: true)
    }

    private func stamp(_ text: String, _ color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 5))
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            .rotationEffect(.degrees(angle))
            .padding(28)
            .accessibilityHidden(true)
    }

    private func decide(trayed: Bool) {
        guard !deciding, index < items.count else { return }
        deciding = true
        if trayed { tray.add([items[index].id]) } else { tray.keep([items[index].id]) }
        let fling = Duration.milliseconds(reduceMotion ? 0 : 250)
        withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.25)) {
            offset = CGSize(width: trayed ? -700 : 700, height: offset.height + 60)
        }
        Task {
            try? await Task.sleep(for: fling)
            advance(trayed: trayed)
            deciding = false
        }
    }

    /// Next item; `trayed` says whether this one went to the tray (Make Still puts it there itself).
    private func advance(trayed: Bool) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
            history.append((index, trayed))
            index += 1
            offset = .zero
        }
    }

    /// The last card comes back from the side it left by, with a bounce.
    private func undo() {
        guard let last = history.popLast() else { return }
        if last.trayed { tray.remove([items[last.index].id]) } else { tray.unkeep([items[last.index].id]) }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            index = last.index
            offset = reduceMotion ? .zero : CGSize(width: last.trayed ? -500 : 500, height: 40)
        }
        Task { withAnimation(.spring(duration: 0.5, bounce: 0.45)) { offset = .zero } }
    }
}

/// Similar shots side by side, two at a time (swipe through the group), zoomed and panned together.
/// The crowned shot is the keeper; tap another to make it the keeper (the old one goes to the tray, unless guarded).
struct SimilarCompareView: View {
    let group: [AssetRecord] // keeper first
    @Environment(DeleteTray.self) private var tray
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keeper: String
    @State private var page = 0
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero

    init(group: [AssetRecord]) {
        self.group = group
        _keeper = State(initialValue: group.first?.id ?? "")
    }

    var body: some View {
        let pair = [group[min(page, group.count - 1)], group[min(page + 1, group.count - 1)]]
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(Array(pair.enumerated()), id: \.element.id) { i, record in pane(record, i) }
                }
                .frame(maxHeight: .infinity)
                .gesture(MagnifyGesture()
                    .onChanged { zoom = min(6, max(1, zoomStart * $0.magnification)) }
                    .onEnded { _ in zoomStart = zoom; if zoom == 1 { pan = .zero; panStart = .zero } })
                .simultaneousGesture(DragGesture(minimumDistance: 10)
                    .onChanged { g in
                        if zoom > 1 { pan = CGSize(width: panStart.width + g.translation.width, height: panStart.height + g.translation.height) }
                    }
                    .onEnded { g in
                        if zoom > 1 { panStart = pan } else if g.translation.width < -60 { turn(1) } else if g.translation.width > 60 { turn(-1) }
                    })
                if group.count > 2 {
                    HStack(spacing: 6) {
                        ForEach(0..<(group.count - 1), id: \.self) { i in
                            Capsule().fill(i == page ? Color.primary : Color.secondary.opacity(0.4)).frame(width: i == page ? 18 : 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("Tap a shot to keep it instead. Pinch to zoom both (pinch in to reset); swipe for the next pair.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background { CleanerBackdrop(tint: .indigo, accent: .yellow) }
            .navigationTitle("Compare \(page + 1)–\(page + 2) of \(group.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("compareDone") }
            }
            .animation(reduceMotion ? nil : .snappy, value: page)
            .animation(.snappy, value: keeper)
        }
    }

    private func pane(_ record: AssetRecord, _ i: Int) -> some View {
        let isKeeper = record.id == keeper
        let inTray = tray.contains(record.id)
        return VStack(spacing: 8) {
            AssetMediaView(record: record, controls: false)
                .scaleEffect(zoom)
                .offset(pan)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isKeeper ? Color.yellow : .white.opacity(0.2), lineWidth: isKeeper ? 3 : 1))
                .overlay(alignment: .top) {
                    if isKeeper {
                        Image(systemName: "crown.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                            .padding(10)
                            .cleanerGlass(Circle())
                            .offset(y: -6)
                            .symbolEffect(.bounce, value: keeper)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Label(isKeeper ? "Keeper" : inTray ? "In tray" : "Kept", systemImage: isKeeper ? "crown" : inTray ? "trash" : "heart")
                .font(.footnote.bold())
                .foregroundStyle(isKeeper ? .yellow : inTray ? .red : .green)
            Text(record.created?.formatted(date: .omitted, time: .standard) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isKeeper else { return }
            tray.makeKeeper(record.id, in: group)
            keeper = record.id
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.spokenDescription), \(isKeeper ? "Keeper" : inTray ? "In delete tray" : "Kept")")
        .accessibilityHint(isKeeper ? "" : "Double-tap to keep this one instead.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("comparePane-\(i)")
    }

    private func turn(_ step: Int) {
        page = min(max(0, page + step), group.count - 2)
    }
}
