import Photos
import SwiftUI
import UIKit

// The cleaner's look: a deep, slowly drifting gradient behind Liquid Glass (iOS 26+) or thin material (iOS 18–25).

extension CleanupCategory {
    var tint: Color {
        switch self {
        case .screenshots: .blue
        case .similar: .indigo
        case .blurry: .cyan
        case .utility: .brown
        case .sensitive: .pink
        case .largeVideos: .purple
        case .accidental: .orange
        case .moments: .teal
        case .chats: .green
        }
    }
}

/// A full-screen mesh gradient tinted by `tint` and `accent`. It drifts slowly; static with Reduce Motion and while off-screen.
struct CleanerBackdrop: View {
    var tint: Color = .indigo
    var accent: Color = .purple
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !visible)) { context in
            let t = reduceMotion ? 0 : Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            let d = { (speed: Float) in sin(t * speed) * 0.12 }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + d(0.21), 0], [1, 0],
                [0, 0.45 + d(0.17)], [0.5 + d(0.13), 0.5 + d(0.19)], [1, 0.55 + d(0.23)],
                [0, 1], [0.5 + d(0.11), 1], [1, 1],
            ], colors: colors)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private var colors: [Color] {
        // Dark: deep, with the tints well below full brightness so white text keeps its contrast. Light: pale washes.
        let base = scheme == .dark ? Color(red: 0.03, green: 0.03, blue: 0.08) : Color(red: 0.97, green: 0.97, blue: 0.99)
        let strong = scheme == .dark ? 0.45 : 0.72, soft = scheme == .dark ? 0.7 : 0.85
        let t = tint.mix(with: base, by: strong), a = accent.mix(with: base, by: strong)
        let ts = tint.mix(with: base, by: soft), aSoft = accent.mix(with: base, by: soft)
        return [t, base, a,
                ts, base, aSoft,
                a, ts, t]
    }
}

/// Liquid Glass on iOS 26+, thin material before, a solid fill with Reduce Transparency.
struct CleanerGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        if solid {
            content.background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color(.secondarySystemBackground)), in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background { if let tint { shape.fill(tint.opacity(0.6)) } }
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}

extension View {
    func cleanerGlass(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(CleanerGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), tint: tint, interactive: interactive))
    }

    func cleanerGlass(_ shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(CleanerGlass(shape: shape, tint: tint, interactive: interactive))
    }

    /// The main action on a screen: prominent glass on iOS 26+, bordered prominent before.
    @ViewBuilder func cleanerProminent(_ tint: Color) -> some View {
        if #available(iOS 26.0, *) { buttonStyle(.glassProminent).tint(tint) } else { buttonStyle(.borderedProminent).tint(tint) }
    }

    /// Big bold rounded numbers that roll when they change.
    func cleanerNumber(_ style: Font.TextStyle = .largeTitle) -> some View {
        font(.system(style, design: .rounded, weight: .heavy)).monospacedDigit().contentTransition(.numericText())
    }
}

/// A small square thumbnail by asset id, from what's already on the iPhone (never downloads): mosaics, fans, celebration.
struct CleanerThumb: View {
    let id: String
    var pixels: CGFloat = 160
    @State private var image: UIImage?

    var body: some View {
        Color.primary.opacity(0.08)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .task(id: id) { image = await Self.load(id, pixels: pixels) }
            .accessibilityHidden(true)
    }

    static func load(_ id: String, pixels: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
              let image = await PhotoAnalysis.thumbnail(asset, side: pixels) else { return nil } // local only, like the analysis
        return UIImage(cgImage: image)
    }
}

#if DEBUG
/// Debug-only launch arguments for the UI walkthrough's screenshots (see WalkthroughUITests).
enum CleanerDemo {
    static func has(_ name: String) -> Bool { ProcessInfo.processInfo.arguments.contains("-Tidyroll" + name) }
}
#endif
