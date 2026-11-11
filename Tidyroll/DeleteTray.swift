import Photos

/// The items picked for deletion, kept across launches until they are deleted or taken out.
@MainActor @Observable final class DeleteTray {
    struct State: Codable {
        var ids: Set<String> = []
        /// Items already selected for the user once, so taking one out sticks.
        var offered: Set<String> = []
        /// Similar shots: the shots the user made a group's keeper in place of its best pick (optional: older trays lack it).
        var keepers: Set<String>?
    }

    enum Outcome: Equatable { case deleted(Int), cancelled, timedOut, failed(String) }

    private(set) var state = State()
    @ObservationIgnored let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "Tidyroll/tray.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(State.self, from: data) { state = saved }
    }

    var ids: Set<String> { state.ids }
    var count: Int { state.ids.count }
    func contains(_ id: String) -> Bool { state.ids.contains(id) }

    func toggle(_ id: String) { contains(id) ? remove([id]) : add([id]) }
    func add(_ ids: some Sequence<String>) { change { $0.ids.formUnion(ids) } }
    func remove(_ ids: some Sequence<String>) { change { $0.ids.subtract(ids) } }

    /// Selects the unguarded items not offered before, once: the memory guard keeps favourites, edits and album items out,
    /// and sensitive items are never picked in bulk.
    func preselect(_ items: [AssetRecord]) {
        let new = items.filter { !state.offered.contains($0.id) }
        guard !new.isEmpty else { return }
        change {
            $0.ids.formUnion(new.filter { !$0.isKeptFromBulk }.map(\.id))
            $0.offered.formUnion(new.map(\.id))
        }
    }

    /// The unguarded, non-sensitive items: what Select All adds. With Similar shots' `groups` (keeper first), never a keeper.
    static func selectable(_ items: [AssetRecord], groups: [[AssetRecord]]? = nil) -> [String] {
        let keepers = Set((groups ?? []).map(\.[0].id))
        return items.filter { !$0.isKeptFromBulk && !keepers.contains($0.id) }.map(\.id)
    }

    /// Similar groups with each one's keeper first: the user's pick, else the best pick (already first).
    func keeperFirst(_ groups: [[AssetRecord]]) -> [[AssetRecord]] {
        let picks = state.keepers ?? []
        return groups.map { g in
            guard let i = g.firstIndex(where: { picks.contains($0.id) }), i > 0 else { return g }
            var out = g
            out.insert(out.remove(at: i), at: 0)
            return out
        }
    }

    /// Makes `id` its group's keeper: out of the tray, and the old keeper goes in its place (unless the memory guard keeps it).
    func makeKeeper(_ id: String, in group: [AssetRecord]) {
        guard let old = keeperFirst([group]).first?.first, old.id != id else { return }
        change {
            $0.keepers = ($0.keepers ?? []).subtracting(group.map(\.id)).union([id])
            $0.ids.remove(id)
            if !old.isKeptFromBulk { $0.ids.insert(old.id) }
        }
    }

    private func change(_ edit: (inout State) -> Void) {
        edit(&state)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: file, options: .atomic)
    }

    /// Deletes every tray item in one PhotoKit change (one system confirmation), then drops them from the tray and `library`.
    func commit(_ library: CleanerLibrary, timeout: Duration = .seconds(60)) async -> Outcome {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(state.ids), options: nil)
        var found = Set<String>()
        assets.enumerateObjects { a, _, _ in found.insert(a.localIdentifier) }
        let gone = state.ids.subtracting(found) // deleted elsewhere, or by a call that timed out but went through
        remove(gone)
        library.remove(gone)
        guard assets.count > 0 else { return .deleted(gone.count) }
        do {
            guard try await Self.delete(assets, timeout: timeout) else { return .timedOut }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        remove(found)
        library.remove(found)
        return .deleted(found.count + gone.count)
    }

    /// One deleteAssets change. False when the completion hasn't come back in `timeout`
    /// (on iOS 26 performChanges sometimes never calls it).
    nonisolated static func delete(_ assets: PHFetchResult<PHAsset>, timeout: Duration) async throws -> Bool {
        let once = OnceFlag()
        return try await withCheckedThrowingContinuation { cont in
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.deleteAssets(assets) }) { ok, error in
                guard once.claim() else { return }
                if ok { cont.resume(returning: true) } else { cont.resume(throwing: error ?? CocoaError(.fileWriteUnknown)) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.claim() { cont.resume(returning: false) }
            }
        }
    }
}

/// True for the first caller only, from any thread.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
}
