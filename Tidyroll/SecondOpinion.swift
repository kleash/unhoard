import FoundationModels
import Photos
import Security
import SwiftUI
import UIKit

/// The AI second opinion for borderline photos (Utility shots): memory, utility or accident, with a one-line reason.
/// It only labels: it never deletes or selects. Apple's on-device model (iOS 27+) is free and private and comes first;
/// Claude is opt-in with the user's own key, and the user sees exactly what leaves the iPhone before it's sent.
/// Sensitive and hidden photos are never sent.
enum SecondOpinion {
    static let labels = ["memory", "utility", "accident"]
    static let maxSide: CGFloat = 512, batchSize = 20, maxPerAsk = 100

    struct Verdict: Decodable, Equatable {
        let id: String
        let label: String
        let reason: String
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let instructions = """
    You look at photos from someone's camera roll that scored low on looks, and give each one of three labels:
    - memory: a moment worth keeping, even if imperfect: people, pets, places, events, nights out, blurry family shots.
    - utility: taken to keep information: receipts, labels, whiteboards, screens, products, documents, QR codes, notes.
    - accident: taken by mistake: pocket or floor shots, a finger over the lens, motion blur with no subject.
    When unsure between memory and another label, choose memory: a wrong "utility" can cost someone a memory.
    Give a reason of at most 12 words.
    """

    // MARK: Apple on-device (Foundation Models, iOS 27+)

    /// nil when Apple's on-device model can look at images here; otherwise why not.
    static var appleUnavailableReason: String? {
        guard #available(iOS 27.0, *) else { return "Needs iOS 27" }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: return model.capabilities.contains(.vision) ? nil : "This model can't look at photos"
        case .unavailable(.deviceNotEligible): return "This iPhone doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading"
        case .unavailable: return "Apple Intelligence isn't available"
        }
    }

    @available(iOS 27.0, *)
    static func appleVerdict(_ image: CGImage) async throws -> (label: String, reason: String) {
        let session = LanguageModelSession(instructions: instructions)
        let answer = try await session.respond(generating: OnDeviceVerdict.self) {
            "Label this photo."
            Attachment(image)
        }.content
        return ("\(answer.label)", answer.reason)
    }

    // MARK: Claude (opt-in)

    /// A JPEG of at most 512 px, drawn fresh from pixels, so no location, dates or camera data go along.
    static func jpeg(_ image: CGImage) -> Data {
        let s = min(1, maxSide / CGFloat(max(image.width, image.height)))
        let size = CGSize(width: (CGFloat(image.width) * s).rounded(), height: (CGFloat(image.height) * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.7) { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// One Messages API request for up to `batchSize` photos, with ids "1"..."n" in `sent` order.
    /// Sensitive items are dropped here, whatever the caller passes.
    static func claudeRequest(_ items: [(record: AssetRecord, jpeg: Data)], apiKey: String) throws -> (request: URLRequest, sent: [AssetRecord]) {
        let sent = items.filter { !$0.record.isSensitive }
        var content: [[String: Any]] = []
        for (i, item) in sent.enumerated() {
            content.append(["type": "text", "text": "Photo id \(i + 1):"])
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": item.jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": "Label each of these \(sent.count) photos, one result per id."])
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
        }
        let verdict = object(["id": ["type": "string"], "label": ["type": "string", "enum": labels] as [String: Any], "reason": ["type": "string"]])
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        // Thinking can't be turned off on this model; low effort keeps a classification cheap.
        let schema: [String: Any] = object(["results": ["type": "array", "items": verdict] as [String: Any]])
        let output: [String: Any] = ["effort": "low", "format": ["type": "json_schema", "schema": schema] as [String: Any]]
        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": output,
            "system": instructions,
            "messages": [["role": "user", "content": content] as [String: Any]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return (request, sent.map(\.record))
    }

    static func claudeVerdicts(_ request: URLRequest, session: URLSession = .shared) async throws -> [Verdict] {
        let (data, response) = try await session.data(for: request)
        return try parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, apiKey: request.value(forHTTPHeaderField: "x-api-key") ?? "")
    }

    /// Claude's verdicts from a Messages API response; errors are user-facing and never contain the key.
    static func parse(_ data: Data, status: Int, apiKey: String) throws -> [Verdict] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw Failure("That API key was rejected")
            case 429: throw Failure("Rate limited, try again shortly")
            default:
                let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "Request failed (HTTP \(status))"
                throw Failure(apiKey.isEmpty ? message : message.replacingOccurrences(of: apiKey, with: "•••"))
            }
        }
        switch json?["stop_reason"] as? String {
        case "refusal": throw Failure("Claude declined to look at these photos")
        case "max_tokens": throw Failure("Claude's answer was cut off")
        default: break
        }
        struct Results: Decodable { let results: [Verdict] }
        guard let blocks = json?["content"] as? [[String: Any]],
              let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let answer = try? JSONDecoder().decode(Results.self, from: Data(text.utf8))
        else { throw Failure("Claude's answer couldn't be read") }
        return answer.results.filter { labels.contains($0.label) }
    }

    /// The local thumbnails to ask about, as the JPEGs that would be sent: hidden and sensitive photos are left out.
    static func previews(_ records: [AssetRecord]) async -> [(record: AssetRecord, jpeg: Data)] {
        var out: [(record: AssetRecord, jpeg: Data)] = []
        for r in records where !r.isSensitive {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [r.id], options: nil).firstObject, !asset.isHidden,
                  let image = await PhotoAnalysis.thumbnail(asset, side: maxSide) else { continue }
            out.append((r, jpeg(image)))
        }
        return out
    }
}

@available(iOS 27.0, *)
@Generable struct OnDeviceVerdict {
    var label: OnDeviceLabel
    @Guide(description: "Why, in at most 12 words")
    var reason: String
}

@available(iOS 27.0, *)
@Generable enum OnDeviceLabel { case memory, utility, accident }

/// The user's Anthropic API key, only in this device's Keychain.
enum CleanerKeyStore {
    private static let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.kleash.tidyroll.anthropic", kSecAttrAccount: "api-key"]

    static func save(_ key: String) throws {
        delete()
        var add = query
        add[kSecValueData] = Data(key.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw SecondOpinion.Failure("Couldn't save the key in the Keychain.") }
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}

/// The Second Opinion menu for a category's borderline items: on this iPhone, or Claude after consent.
struct SecondOpinionButton: View {
    let items: [AssetRecord]
    @Environment(CleanerLibrary.self) private var library
    @State private var settings = false
    @State private var consent = false
    @State private var progress: String?
    @State private var failure: String?

    private var pending: [AssetRecord] { items.filter { $0.aiLabel == nil && !$0.isSensitive } }

    var body: some View {
        let appleReason = SecondOpinion.appleUnavailableReason
        Menu {
            Button { Task { await askApple() } } label: {
                Label("On This iPhone", systemImage: "iphone")
                Text(appleReason ?? "Free and private")
            }
            .disabled(appleReason != nil || pending.isEmpty)
            Button { if CleanerKeyStore.load() == nil { settings = true } else { consent = true } } label: {
                Label("Ask Claude…", systemImage: "sparkles")
                Text("Sends small previews to Anthropic")
            }
            .disabled(pending.isEmpty)
            .accessibilityIdentifier("askClaude")
            Button("Second Opinion Settings", systemImage: "gearshape") { settings = true }
        } label: {
            if let progress { Text(progress).monospacedDigit() } else { Label("Second Opinion", systemImage: "sparkles") }
        }
        .disabled(progress != nil || library.isScanning)
        .accessibilityIdentifier("secondOpinionButton")
        .sheet(isPresented: $settings) { SecondOpinionSettings() }
        .sheet(isPresented: $consent) { SecondOpinionConsentSheet(records: Array(pending.prefix(SecondOpinion.maxPerAsk))).environment(library) }
        .alert("Second opinion stopped", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK") {}
        } message: { Text(failure ?? "") }
    }

    private func askApple() async {
        guard #available(iOS 27.0, *) else { return }
        let todo = pending
        var opinions: [String: (label: String, reason: String)] = [:]
        for (n, r) in todo.enumerated() {
            progress = "\(n + 1) of \(todo.count)"
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [r.id], options: nil).firstObject, !asset.isHidden,
                  let image = await PhotoAnalysis.thumbnail(asset, side: SecondOpinion.maxSide) else { continue }
            do {
                opinions[r.id] = try await SecondOpinion.appleVerdict(image)
            } catch {
                failure = error.localizedDescription
                break
            }
            if opinions.count == 10 { library.setOpinions(opinions); opinions = [:] } // saves the cache every 10, not every photo
        }
        library.setOpinions(opinions)
        progress = nil
    }
}

/// Shows the exact previews that would go to Anthropic, and sends them only on Send.
struct SecondOpinionConsentSheet: View {
    let records: [AssetRecord]
    @Environment(CleanerLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var previews: [(record: AssetRecord, jpeg: Data)]?
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text((previews?.count ?? records.count).formatted()).cleanerNumber()
                        Text("previews to Claude?").font(.title3.bold())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("consentTitle")
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Only these pictures leave your iPhone: at most 512 pixels, with no location, dates or camera details.", systemImage: "photo.fill")
                        Label("Claude labels each as a memory, a utility shot or an accident. Nothing is deleted or selected.", systemImage: "tag.fill")
                        Label("Sensitive and hidden photos are never sent. Your key is billed by Anthropic.", systemImage: "lock.fill")
                    }
                    .padding()
                    .cleanerGlass(tint: .orange.opacity(0.12))
                    if let previews {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(previews, id: \.record.id) { p in
                                Color(.secondarySystemFill)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { UIImage(data: p.jpeg).map { Image(uiImage: $0).resizable().scaledToFill() } }
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .accessibilityLabel(p.record.spokenDescription)
                            }
                        }
                        .padding(8)
                        .cleanerGlass()
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let message { Text(message).foregroundStyle(.red) }
                }
                .font(.subheadline)
                .padding()
            }
            .background { CleanerBackdrop(tint: .orange, accent: .purple) }
            .navigationTitle("Ask Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("consentCancel") }
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await send() } } label: {
                    Group { if sending { ProgressView() } else { Text("Send \(previews?.count ?? 0) Previews") } }.frame(maxWidth: .infinity)
                }
                .cleanerProminent(.orange)
                .controlSize(.large)
                .disabled(sending || (previews ?? []).isEmpty)
                .padding()
                .accessibilityIdentifier("consentSend")
            }
        }
        .interactiveDismissDisabled(sending)
        .task { previews = await SecondOpinion.previews(records) }
    }

    private func send() async {
        guard let previews, let key = CleanerKeyStore.load() else { return }
        sending = true
        message = nil
        do {
            for start in stride(from: 0, to: previews.count, by: SecondOpinion.batchSize) {
                let batch = Array(previews[start..<min(start + SecondOpinion.batchSize, previews.count)])
                let (request, sent) = try SecondOpinion.claudeRequest(batch, apiKey: key)
                var opinions: [String: (label: String, reason: String)] = [:]
                for v in try await SecondOpinion.claudeVerdicts(request) {
                    guard let i = Int(v.id), sent.indices.contains(i - 1) else { continue }
                    opinions[sent[i - 1].id] = (v.label, v.reason)
                }
                library.setOpinions(opinions)
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
        sending = false
    }
}

/// Paste or remove the Anthropic key; shows whether Apple's on-device model is available.
struct SecondOpinionSettings: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var saved = CleanerKeyStore.load() != nil
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.yellow, .orange)
                            .symbolEffect(.breathe)
                            .accessibilityHidden(true)
                        Text("A second opinion").font(.system(.title, design: .rounded, weight: .heavy))
                        Text("For borderline Utility shots: is it a memory, a utility shot or an accident? It only labels; it never deletes or selects.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("On this iPhone") {
                    Label(SecondOpinion.appleUnavailableReason.map { "Apple Intelligence: \($0)." } ?? "Apple Intelligence is ready. It's free and nothing leaves your iPhone.",
                          systemImage: SecondOpinion.appleUnavailableReason == nil ? "checkmark.seal.fill" : "iphone.slash")
                }
                Section {
                    SecureField(saved ? "A key is saved — paste to replace" : "Anthropic API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("apiKeyField")
                    Button("Save") {
                        do {
                            try CleanerKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                            key = ""
                            saved = true
                            message = "Key saved on this iPhone."
                        } catch { message = error.localizedDescription }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("apiKeySave")
                    if saved {
                        Button("Remove Key", role: .destructive) {
                            CleanerKeyStore.delete()
                            saved = false
                            message = "Key removed."
                        }
                        .accessibilityIdentifier("apiKeyRemove")
                    }
                    Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Optional. When you ask Claude, Tidyroll first shows the small previews it will send to Anthropic with your key; usage is billed to your Anthropic account. Sensitive and hidden photos are never sent.")
                }
                if !message.isEmpty { Text(message) }
            }
            .scrollContentBackground(.hidden)
            .background { CleanerBackdrop(tint: .orange, accent: .purple) }
            .navigationTitle("Second Opinion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone") }
        }
    }
}
