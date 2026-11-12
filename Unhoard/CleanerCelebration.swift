import Charts
import StoreKit
import SwiftUI

/// What each delete cleared, kept on this iPhone (one small JSON file) for the history chart.
enum CleanerHistory {
    struct Entry: Codable, Hashable {
        var date: Date
        var bytes: Int64
        var count: Int
    }

    static let file = URL.applicationSupportDirectory.appending(path: "Unhoard/history.json")

    static func load(_ file: URL = file) -> [Entry] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    static func record(_ entry: Entry, to file: URL = file) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(load(file) + [entry]).write(to: file, options: .atomic)
    }
}

/// After a delete: the thumbnails fly into the bin, confetti, then what was cleared (space returns once Recently Deleted is emptied).
struct CleanerCelebration: View {
    struct Summary {
        var bytes: Int64
        var count: Int
        /// The whole library's size before the delete.
        var libraryBytes: Int64
        var images: [UIImage]
        /// The screenshot count line to share instead of the plain message (see `CleanerLibrary.screenshotCountLine`).
        var countLine: String?

        var lighter: String {
            let p = Double(bytes) / Double(max(libraryBytes, 1)) * 100
            return p < 1 ? "less than 1%" : "\(Int(p.rounded()))%"
        }
    }

    let summary: Summary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @State private var flown = false
    @State private var landed = 0
    @State private var revealed = false
    @State private var history = false

    var body: some View {
        ZStack {
            CleanerBackdrop(tint: .green, accent: .teal)
            if revealed && !reduceMotion { CleanerConfetti().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 96))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green.gradient)
                        .symbolEffect(.bounce, value: landed)
                    if !reduceMotion {
                        ForEach(summary.images.indices, id: \.self) { i in
                            let n = Double(summary.images.count)
                            Image(uiImage: summary.images[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .rotationEffect(.degrees(flown ? 40 : (Double(i) - n / 2) * 8))
                                .scaleEffect(flown ? 0.1 : 1)
                                .offset(flown ? .zero : CGSize(width: (Double(i) - (n - 1) / 2) * 40, height: -190 + abs(Double(i) - (n - 1) / 2) * 12))
                                .opacity(flown ? 0 : 1)
                                .animation(.easeIn(duration: 0.55).delay(0.3 + Double(i) * 0.08), value: flown)
                        }
                    }
                }
                .frame(height: 280, alignment: .bottom)
                .accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text("You cleared").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Text(summary.bytes.formatted(.byteCount(style: .file)))
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("\(summary.count.formatted()) \(summary.count == 1 ? "item" : "items") · your library is \(summary.lighter) lighter")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    // PhotoKit can't empty Recently Deleted, and Apple documents no link to it: the steps instead.
                    Text("The space comes back when Recently Deleted is emptied, which iPhone does after 30 days. To get it now: in Photos, open Recently Deleted (under Utilities), tap Select, then Delete All.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .cleanerGlass(tint: .green.opacity(0.15))
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 30)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("celebrationSummary")
                Spacer()
                // Text only: never the user's photos, and no numbers about their library beyond the screenshot count line.
                ShareLink(item: summary.countLine
                          ?? "Unhoard cleans up your iPhone photos — free, open source, nothing leaves your phone. https://kleash.github.io/unhoard/") {
                    Label("Send to someone with a full iPhone", systemImage: "square.and.arrow.up")
                }
                .font(.subheadline.weight(.semibold))
                .opacity(revealed ? 1 : 0)
                .accessibilityIdentifier("celebrationShare")
                HStack(spacing: 12) {
                    Button { history = true } label: {
                        Label("History", systemImage: "chart.bar.fill").frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 14)
                    .cleanerGlass(Capsule(), interactive: true)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("celebrationHistory")
                    Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .cleanerProminent(.green)
                        .controlSize(.large)
                        .accessibilityIdentifier("celebrationDone")
                }
                .font(.headline)
            }
            .padding(24)
        }
        .sensoryFeedback(.success, trigger: revealed)
        .sheet(isPresented: $history) { CleanerHistoryView() }
        .task {
            flown = true
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(850 + 80 * summary.images.count)) }
            landed += 1
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.3)) { revealed = true }
            // After the second clean-up ever (the delete has been recorded by now); the system caps how often it shows.
            if CleanerHistory.load().count == 2 { requestReview() }
        }
    }
}

/// A short burst of confetti on a Canvas: about 3 seconds, then it stops drawing.
struct CleanerConfetti: View {
    private struct Bit {
        var x, vx, vy, spin: Double
        var color: Color
    }

    @State private var bits: [Bit] = (0..<90).map { _ in
        Bit(x: .random(in: 0.2...0.8), vx: .random(in: -260...260), vy: .random(in: -900 ... -450), spin: .random(in: -8...8),
            color: [Color.green, .yellow, .pink, .cyan, .orange, .purple, .white].randomElement()!)
    }
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            Canvas { gc, size in
                let t = context.date.timeIntervalSince(start)
                for b in bits {
                    let x = b.x * size.width + b.vx * t
                    let y = size.height * 0.62 + b.vy * t + 300 * t * t // thrown up from behind the summary, then falling
                    var piece = gc
                    piece.opacity = max(0, 1 - t / 3)
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(b.spin * t))
                    piece.fill(Path(CGRect(x: -4, y: -7, width: 8, height: 14)), with: .color(b.color))
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.2))
            finished = true
        }
        .accessibilityHidden(true)
    }
}

/// Everything cleared so far, as a chart by day.
struct CleanerHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [CleanerHistory.Entry] = []

    var body: some View {
        let total = entries.reduce(Int64(0)) { $0 + $1.bytes }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cleared so far").font(.headline).foregroundStyle(.secondary)
                        Text(total.formatted(.byteCount(style: .file))).cleanerNumber()
                        Text("\(entries.reduce(0) { $0 + $1.count }.formatted()) items over \(entries.count.formatted()) \(entries.count == 1 ? "clean-up" : "clean-ups")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if entries.isEmpty {
                        ContentUnavailableView("Nothing cleared yet", systemImage: "chart.bar",
                                               description: Text("Each time you delete, what you cleared shows up here."))
                    } else {
                        Chart(entries, id: \.date) { e in
                            BarMark(x: .value("Day", e.date, unit: .day), y: .value("Cleared (MB)", Double(e.bytes) / 1_000_000))
                                .foregroundStyle(.green.gradient)
                                .cornerRadius(6)
                        }
                        .chartYAxisLabel("MB")
                        .frame(height: 240)
                        ForEach(entries.reversed(), id: \.date) { e in
                            HStack {
                                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text("\(e.count) items · \(e.bytes.formatted(.byteCount(style: .file)))").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding()
                .cleanerGlass()
                .padding()
            }
            .background { CleanerBackdrop(tint: .green, accent: .blue) }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("historyDone") }
        }
        .onAppear {
            entries = CleanerHistory.load()
            #if DEBUG
            if entries.isEmpty, CleanerDemo.has("CelebrationDemo") { entries = CleanerHistory.sample }
            #endif
        }
    }
}

#if DEBUG
extension CleanerHistory {
    /// Sample history for the walkthrough's screenshot (never saved).
    static let sample: [Entry] = [(-26, 412, 31), (-19, 1_380, 96), (-12, 260, 18), (-6, 2_150, 140), (-2, 640, 44), (0, 1_234, 86)].map {
        Entry(date: Date.now.addingTimeInterval(Double($0.0) * 86_400), bytes: Int64($0.1) * 1_000_000, count: $0.2)
    }
}
#endif
