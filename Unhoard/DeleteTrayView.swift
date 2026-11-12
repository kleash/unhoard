import SwiftUI

/// The floating Delete button shown over every cleaner screen while the tray has items; opens the commit sheet.
/// With a `scope` (a category's items), it counts and deletes only the tray items in it; on the home screen, the whole tray.
struct DeleteButton: View {
    var scope: Set<String>? = nil
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray
    @State private var showing = false

    var body: some View {
        let ids = scope.map { tray.ids.intersection($0) } ?? tray.ids
        let count = ids.count
        let bytes = ids.reduce(Int64(0)) { $0 + (library.records[$1]?.bytes ?? 0) }
        Button { showing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill").symbolEffect(.bounce, value: count)
                Text("Delete \(count.formatted())").contentTransition(.numericText())
                Text(bytes.formatted(.byteCount(style: .file)))
                    .font(.headline.monospacedDigit())
                    .opacity(0.85)
                    .contentTransition(.numericText())
            }
            .font(.headline)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .cleanerGlass(Capsule(), tint: .red, interactive: true)
            .shadow(color: .red.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .opacity(count > 0 ? 1 : 0)
        .scaleEffect(count > 0 ? 1 : 0.8)
        .disabled(count == 0)
        .accessibilityHidden(count == 0)
        .accessibilityLabel("Delete \(count) items, \(bytes.formatted(.byteCount(style: .file)))")
        .accessibilityHint("Review the delete tray and confirm.")
        .accessibilityIdentifier("deleteButton")
        .animation(.snappy, value: count)
        .sheet(isPresented: $showing) {
            DeleteCommitSheet(ids: ids).environment(library).environment(tray)
        }
    }
}

/// The tray's items (tap to take one out, tap again to put it back), what deleting means, and the one Delete action.
/// After a delete, the celebration takes over the sheet.
struct DeleteCommitSheet: View {
    let ids: Set<String>
    @Environment(CleanerLibrary.self) private var library
    @Environment(DeleteTray.self) private var tray
    @Environment(\.dismiss) private var dismiss
    @State private var shown: [AssetRecord] = []
    @State private var deleting = false
    @State private var message: String?
    @State private var done = 0
    @State private var celebration: CleanerCelebration.Summary?

    var body: some View {
        Group {
            if let celebration { CleanerCelebration(summary: celebration) } else { trayContent }
        }
        .onAppear {
            shown = ids.compactMap { library.records[$0] }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        }
        .sensoryFeedback(.success, trigger: done)
        .interactiveDismissDisabled(deleting)
    }

    private var trayContent: some View {
        let selected = shown.filter { tray.contains($0.id) }
        let videos = selected.count(where: \.isVideo)
        let bytes = selected.reduce(Int64(0)) { $0 + $1.bytes }
        return NavigationStack {
            AssetGrid(items: shown) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selected.count.formatted()).cleanerNumber()
                        Text(selected.count == 1 ? "item" : "items").font(.headline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(bytes.formatted(.byteCount(style: .file, spellsOutZero: false))).cleanerNumber(.title).foregroundStyle(.red)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityElement(children: .combine)
                    Text("\(selected.count - videos) photos · \(videos) videos").font(.subheadline).foregroundStyle(.secondary)
                    Divider()
                    Label("They stay in Recently Deleted for 30 days, so you can still get them back.", systemImage: "clock.arrow.circlepath")
                    Label("If your library is an iCloud Shared Library, deleting removes items for everyone in it.", systemImage: "person.2")
                    Label("Tap an item to keep it.", systemImage: "hand.tap").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cleanerGlass(tint: .red.opacity(0.12))
                .padding()
                .animation(.snappy, value: selected.count)
            }
            .background { CleanerBackdrop(tint: .red, accent: .orange) }
            .navigationTitle("Delete Tray")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Keep All") { tray.remove(shown.map(\.id)) }.disabled(selected.isEmpty || deleting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let message {
                        Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Button(role: .destructive) {
                        Task { await commit(selected) }
                    } label: {
                        Group {
                            if deleting { ProgressView() } else { Label("Delete \(selected.count) Items", systemImage: "trash.fill") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .cleanerProminent(.red)
                    .controlSize(.large)
                    .disabled(selected.isEmpty || deleting)
                    .accessibilityIdentifier("commitDeleteButton")
                }
                .padding()
            }
        }
    }

    private func commit(_ selected: [AssetRecord]) async {
        deleting = true
        message = nil
        // Taken before the delete: afterwards the photos (and their thumbnails) are gone.
        let libraryBytes = library.records.values.reduce(Int64(0)) { $0 + $1.bytes }
        let bytes = selected.reduce(Int64(0)) { $0 + $1.bytes }
        var images: [UIImage] = []
        for r in selected.prefix(8) { if let i = await CleanerThumb.load(r.id, pixels: 200) { images.append(i) } }
        let outcome = await tray.commit(library, ids: Set(selected.map(\.id)))
        deleting = false
        switch outcome {
        case .deleted(let count):
            done += 1
            CleanerHistory.record(CleanerHistory.Entry(date: .now, bytes: bytes, count: count))
            celebration = .init(bytes: bytes, count: count, libraryBytes: libraryBytes, images: images, countLine: library.screenshotCountLine)
        case .cancelled:
            break
        case .timedOut:
            message = "Photos didn't confirm the deletion. Check Recently Deleted, then tap Delete to try again."
        case .failed(let reason):
            message = "Couldn't delete: \(reason)"
        }
    }
}
