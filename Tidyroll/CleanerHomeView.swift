import Charts
import SwiftUI

struct CleanerHomeView: View {
    let limited: Bool
    @Environment(CleanerLibrary.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [CleanupCategory] = []
    @State private var settings = false
    @State private var history = false
    @State private var demo: CleanerCelebration.Summary?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    if limited {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Tidyroll can see only the photos you picked. Allow Full Access to clean your whole library.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                            Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                                .font(.callout.bold())
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cleanerGlass(tint: .orange.opacity(0.25))
                    }
                    CleanerHero { path.append($0) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(CleanupCategory.allCases) { category in
                            NavigationLink(value: category) { CategoryCard(category: category) }
                                .buttonStyle(.plain)
                        }
                    }
                    Label("Everything stays on this iPhone unless you ask Claude for a second opinion.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background { CleanerBackdrop(tint: .indigo, accent: .pink) }
            .navigationTitle("Tidyroll")
            .navigationDestination(for: CleanupCategory.self) { CategoryGridView(category: $0) }
            .refreshable { await library.scan() }
            .safeAreaInset(edge: .bottom) { DeleteButton() }
            .toolbar {
                Button("History", systemImage: "chart.bar.xaxis") { history = true }.accessibilityIdentifier("historyButton")
                Button("Second Opinion Settings", systemImage: "sparkles") { settings = true }.accessibilityIdentifier("settingsButton")
            }
            .sheet(isPresented: $settings) { SecondOpinionSettings() }
            .sheet(isPresented: $history) { CleanerHistoryView() }
            .sheet(isPresented: Binding { demo != nil } set: { if !$0 { demo = nil } }) {
                if let demo { CleanerCelebration(summary: demo) }
            }
        }
        #if DEBUG
        .task {
            guard CleanerDemo.has("CelebrationDemo") else { return }
            var images: [UIImage] = []
            for r in library.records.values.filter({ $0.isPhoto && !$0.isSensitive }).prefix(8) {
                if let i = await CleanerThumb.load(r.id, pixels: 200) { images.append(i) }
            }
            demo = .init(bytes: 1_234_000_000, count: 86, libraryBytes: 30_000_000_000, images: images)
        }
        #endif
    }
}

/// Library bytes by cleanup category, each item counted once (in its first category), biggest first;
/// then everything else (`category` nil): the memories.
struct LibrarySlice: Identifiable {
    var category: CleanupCategory?
    var bytes: Int64
    var id: String { category?.rawValue ?? "memories" }

    @MainActor static func slices(_ library: CleanerLibrary) -> [LibrarySlice] {
        var seen = Set<String>()
        var out: [LibrarySlice] = []
        for c in CleanupCategory.allCases {
            let bytes = (library.sections[c] ?? []).reduce(Int64(0)) { seen.insert($1.id).inserted ? $0 + $1.bytes : $0 }
            if bytes > 0 { out.append(LibrarySlice(category: c, bytes: bytes)) }
        }
        out.sort { $0.bytes > $1.bytes }
        let total = library.records.values.reduce(Int64(0)) { $0 + $1.bytes }
        return out + [LibrarySlice(category: nil, bytes: max(0, total - out.reduce(0) { $0 + $1.bytes }))]
    }
}

/// The home screen's hero: while scanning, a live mosaic of what was just looked at and a growing "you can free" total;
/// afterwards, a ring of the library by size (tap a slice to open its category).
struct CleanerHero: View {
    let open: (CleanupCategory) -> Void
    @Environment(CleanerLibrary.self) private var library
    @State private var angle: Double?

    var body: some View {
        let slices = LibrarySlice.slices(library)
        let cleanable = slices.filter { $0.category != nil }.reduce(Int64(0)) { $0 + $1.bytes }
        Group {
            if let status = library.status {
                VStack(alignment: .leading, spacing: 14) {
                    CleanerMosaic(ids: library.recent)
                        .frame(height: 132)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(cleanable.formatted(.byteCount(style: .file, spellsOutZero: false))).cleanerNumber()
                            Text("you can free so far").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(library.fraction * 100))%").cleanerNumber(.title).foregroundStyle(.tint)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    ProgressView(value: library.fraction)
                    Text(status).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scanStatus")
            } else if !library.records.isEmpty {
                ring(slices, cleanable: cleanable)
            }
        }
        .padding(16)
        .cleanerGlass()
        .animation(.snappy, value: cleanable)
        .animation(.snappy, value: library.fraction)
        .animation(.smooth, value: library.status == nil)
    }

    private func ring(_ slices: [LibrarySlice], cleanable: Int64) -> some View {
        let total = slices.reduce(Int64(0)) { $0 + $1.bytes }
        return Chart(slices) { s in
            SectorMark(angle: .value("Size", Double(s.bytes)), innerRadius: .ratio(0.66), angularInset: 1.5)
                .cornerRadius(5)
                .foregroundStyle(s.category?.tint ?? Color.primary.opacity(0.18))
                .accessibilityLabel(s.category?.title ?? "Memories")
                .accessibilityValue(s.bytes.formatted(.byteCount(style: .file)))
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $angle)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectAngleValue(at: proxy.angle(at: $0.location)) } }
        .frame(height: 280)
        .overlay {
            VStack(spacing: 2) {
                Text(cleanable.formatted(.byteCount(style: .file, spellsOutZero: false))).cleanerNumber()
                Text("you can free").font(.subheadline.weight(.semibold))
                Text("of \(total.formatted(.byteCount(style: .file))) · tap a colour").font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: 170)
            .allowsHitTesting(false)
        }
        .onChange(of: angle) { _, value in
            guard let value else { return }
            angle = nil
            var sum = 0.0
            for s in slices {
                sum += Double(s.bytes)
                if value <= sum { if let c = s.category { open(c) }; return }
            }
        }
        .accessibilityHint("The categories below open the same groups.")
        .accessibilityIdentifier("ringChart")
    }
}

/// Thumbnails of what the scan just looked at, streaming across in two rows. Still with Reduce Motion; paused off-screen.
struct CleanerMosaic: View {
    let ids: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    private let side: CGFloat = 64, gap: CGFloat = 4

    var body: some View {
        let rows = [ids.enumerated().filter { $0.offset % 2 == 0 }.map(\.element), ids.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)]
        // The card sets the size; the strips are wider and slide inside it.
        Color.primary.opacity(0.05).overlay(alignment: .leading) {
            TimelineView(.animation(paused: reduceMotion || !visible)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<2, id: \.self) { row in strip(rows[row], shift: t * (row == 0 ? 26 : 18)) }
                }
            }
        }
        .clipped()
        .overlay { if ids.isEmpty { Image(systemName: "photo.stack").font(.largeTitle).foregroundStyle(.secondary).symbolEffect(.pulse) } }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }

    /// One row, repeated so it wraps around seamlessly as it slides left.
    private func strip(_ row: [String], shift: Double) -> some View {
        let span = CGFloat(max(row.count, 1)) * (side + gap)
        let copies = row.isEmpty ? 0 : Int((480 / span).rounded(.up)) + 1
        return HStack(spacing: gap) {
            ForEach(0..<(row.count * copies), id: \.self) { i in
                CleanerThumb(id: row[i % row.count], pixels: 128)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .offset(x: -CGFloat(shift.truncatingRemainder(dividingBy: Double(span))))
        .frame(height: side)
    }
}

struct CategoryCard: View {
    let category: CleanupCategory
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray

    var body: some View {
        let items = library.sections[category] ?? []
        let inTray = items.count(where: { tray.contains($0.id) })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: category.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(category.tint.gradient, in: Circle())
                    .symbolEffect(.bounce, value: items.count)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                fan(items)
            }
            Text(category.title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(items.count.formatted()).cleanerNumber(.title)
                Text(detail(items, inTray: inTray))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cleanerGlass(tint: items.isEmpty ? nil : category.tint.opacity(0.22), interactive: true)
        .opacity(items.isEmpty ? 0.6 : 1)
        .scaleEffect(items.isEmpty ? 0.97 : 1)
        .animation(.spring(duration: 0.5, bounce: 0.4), value: items.isEmpty)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("card-\(category.rawValue)")
    }

    /// The first three items, fanned out like photos on a table (blurred for Sensitive).
    private func fan(_ items: [AssetRecord]) -> some View {
        let first = Array(items.prefix(3))
        return ZStack {
            ForEach(Array(first.enumerated()), id: \.element.id) { i, r in
                CleanerThumb(id: r.id, pixels: 120)
                    .frame(width: 40, height: 40)
                    .blur(radius: category == .sensitive ? 5 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .rotationEffect(.degrees(Double(i - 1) * 12))
                    .offset(x: CGFloat(i - 1) * 14)
                    .zIndex(Double(-i))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 76, height: 46)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func detail(_ items: [AssetRecord], inTray: Int) -> String {
        if category == .utility && library.aestheticsUnsupported { return "Needs an iPhone" }
        guard !items.isEmpty else { return "none yet" }
        var parts = [items.reduce(Int64(0)) { $0 + $1.bytes }.formatted(.byteCount(style: .file))]
        if inTray > 0 { parts.append("\(inTray) in tray") }
        return parts.joined(separator: " · ")
    }
}
