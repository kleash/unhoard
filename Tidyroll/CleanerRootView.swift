import Photos
import SwiftUI

/// The whole cleaner behind one view: it owns its state and asks for full Photos access itself when first shown.
struct CleanerRootView: View {
    @State private var library = CleanerLibrary()
    @State private var tray = DeleteTray()
    @State private var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if CleanerDemo.has("Onboarding") { PhotoAccessView(denied: false) {} } else { content }
            #else
            content
            #endif
        }
        .environment(library)
        .environment(tray)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let now = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if now != access { access = now } else if now == .authorized || now == .limited { Task { await scan() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch access {
        case .authorized, .limited:
            CleanerHomeView(limited: access == .limited)
                .task { await scan() }
        case .notDetermined:
            PhotoAccessView(denied: false) {
                access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
        default:
            PhotoAccessView(denied: true) {}
        }
    }

    private func scan() async {
        await library.scan()
        // Items deleted outside the app leave the tray once a complete scan has seen the whole library.
        if library.hasCompletedScan { tray.remove(tray.ids.filter { library.records[$0] == nil }) }
    }
}

/// Explains why full access is needed before the system prompt, or how to fix a denial in Settings.
struct PhotoAccessView: View {
    let denied: Bool
    let request: () async -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Circle().fill(.indigo.gradient).frame(width: 120, height: 120).blur(radius: 30).opacity(0.8)
                    Image(systemName: denied ? "lock.trianglebadge.exclamationmark.fill" : "sparkles.rectangle.stack.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white, .pink)
                        .symbolEffect(.breathe)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityHidden(true)
                Text(denied ? "Tidyroll can't see your photos" : "Tidy up your camera roll")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                // The privacy promise first, as its own card.
                VStack(alignment: .leading, spacing: 10) {
                    Label("Private by design", systemImage: "lock.shield.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                    Text("Every photo is looked at on this iPhone, with Apple's on-device Vision. No accounts, no analytics, nothing uploaded.")
                    HStack(spacing: 8) {
                        ForEach(["On-device", "No account", "No tracking"], id: \.self) { tag in
                            Text(tag)
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.green.opacity(0.2), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cleanerGlass(tint: .green.opacity(0.12))
                VStack(alignment: .leading, spacing: 16) {
                    point("magnifyingglass", .cyan, "Finds screenshots, similar and blurry shots, large videos and accidental clips across your whole library.")
                    point("heart.fill", .pink, "Favourites, edited photos and photos in your albums are never selected for you.")
                    point("trash.fill", .orange, "Nothing is deleted until you confirm, and deleted items stay in Recently Deleted for 30 days.")
                }
                .padding()
                .cleanerGlass()
                Text(denied
                     ? "Turn on Full Access for Tidyroll in Settings > Privacy & Security > Photos."
                     : "To find what can go and to delete what you choose, Tidyroll needs Full Access. Choose \"Allow Full Access\" on the next screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { CleanerBackdrop(tint: .indigo, accent: .pink) }
        .safeAreaInset(edge: .bottom) {
            Button {
                if denied { openURL(URL(string: UIApplication.openSettingsURLString)!) } else { Task { await request() } }
            } label: {
                Text(denied ? "Open Settings" : "Continue").font(.headline).frame(maxWidth: .infinity)
            }
            .cleanerProminent(.indigo)
            .controlSize(.large)
            .padding(24)
            .accessibilityIdentifier("accessButton")
        }
    }

    private func point(_ symbol: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28)
        }
        .font(.body)
    }
}
