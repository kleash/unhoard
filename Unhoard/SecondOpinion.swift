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

    /// Similar shots: Claude's per-photo answer within a group of near-identical shots.
    static let similarLabels = ["keep", "duplicate"]
    static let similarInstructions = """
    You look at groups of similar photos from someone's camera roll, taken moments apart, and give each photo one of two labels:
    - keep: the best shot of the moment, or a different moment, pose or subject worth keeping on its own.
    - duplicate: a near-identical shot of the same moment that is worse than the best one, so it could be deleted.
    Judge sharpness, eyes open, expressions and framing. Each set of near-identical shots keeps exactly one best shot.
    When a photo isn't really the same shot as another, choose keep: a wrong "duplicate" can cost someone a memory.
    Give a reason of at most 12 words.
    """

    // MARK: Apple on-device (Foundation Models, iOS 27+)

    /// nil when Apple's on-device model can look at images here; otherwise why not.
    static var appleUnavailableReason: String? {
        guard #available(iOS 27.0, *) else { return "Needs iOS 27" }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available: return model.capabilities.contains(.vision) ? nil : "This model can't look at photos"
        case .unavailable(.deviceNotEligible): return "This iPhone doesn't support it"
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn it on in Settings › Apple Intelligence & Siri"
        case .unavailable(.modelNotReady): return "Apple's model is still downloading. iOS shows no progress for it; it needs Wi-Fi and goes faster while charging"
        case .unavailable: return "Not available right now"
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
    /// Sensitive items are dropped here, whatever the caller passes. `prompt` gets the photos as sent.
    static func claudeRequest(_ items: [(record: AssetRecord, jpeg: Data)], apiKey: String, system: String = SecondOpinion.instructions,
                              labels: [String] = SecondOpinion.labels,
                              prompt: ([AssetRecord]) -> String = { "Label each of these \($0.count) photos, one result per id." })
        throws -> (request: URLRequest, sent: [AssetRecord]) {
        let sent = items.filter { !$0.record.isSensitive }
        var content: [[String: Any]] = []
        for (i, item) in sent.enumerated() {
            content.append(["type": "text", "text": "Photo id \(i + 1):"])
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": item.jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": prompt(sent.map(\.record))])
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
            "system": system,
            "messages": [["role": "user", "content": content] as [String: Any]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return (request, sent.map(\.record))
    }

    /// `retries`: how often a rate-limited (429) or overloaded (529) answer is waited out and tried again.
    static func claudeVerdicts(_ request: URLRequest, labels: [String] = SecondOpinion.labels, retries: Int = 0,
                               session: URLSession = .shared) async throws -> [Verdict] {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse, status = http?.statusCode ?? 0
            if [429, 529].contains(status), attempt < retries { // as long as the server asks, else 5, 10, 20… s
                try await Task.sleep(for: .seconds(http?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 5 * pow(2, Double(attempt))))
                attempt += 1
                continue
            }
            return try parse(data, status: status, apiKey: request.value(forHTTPHeaderField: "x-api-key") ?? "", labels: labels)
        }
    }

    /// Verdicts by photo id: Claude's ids "1"..."n" are positions in `sent`; unknown ids are ignored.
    static func opinions(_ verdicts: [Verdict], sent: [AssetRecord]) -> [String: (label: String, reason: String)] {
        var out: [String: (label: String, reason: String)] = [:]
        for v in verdicts {
            guard let i = Int(v.id), sent.indices.contains(i - 1) else { continue }
            out[sent[i - 1].id] = (v.label, v.reason)
        }
        return out
    }

    /// Claude's verdicts from a Messages API response; errors are user-facing and never contain the key.
    static func parse(_ data: Data, status: Int, apiKey: String, labels: [String] = SecondOpinion.labels) throws -> [Verdict] {
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

    /// Similar groups packed whole into requests of up to `batchSize` photos; a bigger group goes alone, its first `batchSize`.
    /// Sensitive photos are left out, and so are groups with fewer than two photos left.
    static func batches(_ groups: [[AssetRecord]]) -> [[[AssetRecord]]] {
        var out: [[[AssetRecord]]] = []
        for g in groups.map({ Array($0.filter { !$0.isSensitive }.prefix(batchSize)) }) where g.count > 1 {
            if let last = out.last, last.joined().count + g.count <= batchSize { out[out.count - 1].append(g) } else { out.append([g]) }
        }
        return out
    }

    /// Tells Claude which of the sent photos ("1"..."n") belong together.
    static func similarPrompt(_ sent: [AssetRecord], groups: [[AssetRecord]]) -> String {
        let index = Dictionary(sent.enumerated().map { ($1.id, $0 + 1) }, uniquingKeysWith: { a, _ in a })
        let sets = groups.map { $0.compactMap { index[$0.id] } }.filter { !$0.isEmpty }
        let text = sets.enumerated().map { "group \($0 + 1) is photos \($1.map(String.init).joined(separator: ", "))" }
        return "These \(sent.count) photos come in groups of similar shots: \(text.joined(separator: "; ")). "
            + "Label each photo against the others in its group, one result per id."
    }
}

extension CleanerLibrary {
    /// Asks Claude about Similar groups one batch (request) at a time, saving each batch's labels as they arrive.
    /// Lives as long as the cleaner, not a screen; it ends when the app does, and asking again sends only unanswered groups.
    func askClaude(_ batches: [[[AssetRecord]]], apiKey: String) {
        guard similarTask == nil, !isScanning, !batches.isEmpty else { return }
        similarError = nil
        similarRun = (0, batches.joined().count)
        similarTask = Task {
            for batch in batches {
                do {
                    let previews = await SecondOpinion.previews(Array(batch.joined()))
                    try Task.checkCancellation()
                    if !previews.isEmpty {
                        let (request, sent) = try SecondOpinion.claudeRequest(previews, apiKey: apiKey, system: SecondOpinion.similarInstructions,
                                                                            labels: SecondOpinion.similarLabels) { SecondOpinion.similarPrompt($0, groups: batch) }
                        let verdicts = try await SecondOpinion.claudeVerdicts(request, labels: SecondOpinion.similarLabels, retries: 4)
                        setOpinions(SecondOpinion.opinions(verdicts, sent: sent), similar: true)
                    }
                    similarRun?.done += batch.count
                } catch {
                    if !Task.isCancelled { similarError = error.localizedDescription }
                    break
                }
            }
            similarRun = nil
            similarTask = nil
        }
    }

    func stopAskingClaude() { similarTask?.cancel() }
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
    private static let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.kleash.unhoard.anthropic", kSecAttrAccount: "api-key"]

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
    @State private var askAfterKey = false // opened Settings from Ask: carry on to the consent sheet once a key is saved
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
            Button { if CleanerKeyStore.load() == nil { askAfterKey = true; settings = true } else { consent = true } } label: {
                Label("Ask Claude (optional)…", systemImage: "sparkles")
                Text("Not needed · sends small previews to Anthropic")
            }
            .disabled(pending.isEmpty)
            .accessibilityIdentifier("askClaude")
            Button("Second Opinion Settings", systemImage: "gearshape") { settings = true }
        } label: {
            if let progress { Text(progress).monospacedDigit() } else { Label("Second Opinion (optional)", systemImage: "sparkles") }
        }
        .disabled(progress != nil || library.isScanning)
        .accessibilityIdentifier("secondOpinionButton")
        .sheet(isPresented: $settings, onDismiss: {
            // A sheet asked for while the last one is still going away is dropped, so wait for it.
            if askAfterKey, CleanerKeyStore.load() != nil { Task { try? await Task.sleep(for: .milliseconds(400)); consent = true } }
            askAfterKey = false
        }) { SecondOpinionSettings(asking: askAfterKey) }
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
    /// Similar shots: every batch to send; `records` is the first one, shown as a sample. Sending starts `CleanerLibrary.askClaude`.
    var batches: [[[AssetRecord]]]? = nil
    @Environment(CleanerLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var previews: [(record: AssetRecord, jpeg: Data)]?
    @State private var sending = false
    @State private var message: String?

    private var count: Int { batches.map { $0.joined().joined().count } ?? previews?.count ?? records.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(count.formatted()).cleanerNumber()
                        Text("previews to Claude?").font(.title3.bold())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("consentTitle")
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Optional. You don't need this: Unhoard finds and cleans everything without Claude.", systemImage: "hand.thumbsup.fill")
                        Label("Only these pictures leave your iPhone: at most 512 pixels, with no location, dates or camera details.", systemImage: "photo.fill")
                        Label(batches == nil ? "Claude labels each as a memory, a utility shot or an accident. Nothing is deleted or selected."
                              : "Claude marks each photo in a group as keep or duplicate. Nothing is deleted or selected.", systemImage: "tag.fill")
                        if let batches, batches.count > 1 {
                            Label("\(batches.joined().count.formatted()) groups go in \(batches.count.formatted()) batches of up to \(SecondOpinion.batchSize) photos, and labels appear as each batch comes back. Below is the first batch. You can stop anytime from Similar Shots.",
                                  systemImage: "square.stack.3d.up.fill")
                        }
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
                    Group { if sending { ProgressView() } else { Text("Send \(batches == nil ? previews?.count ?? 0 : count) Previews") } }.frame(maxWidth: .infinity)
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
        if let batches { library.askClaude(batches, apiKey: key); dismiss(); return }
        sending = true
        message = nil
        do {
            for start in stride(from: 0, to: previews.count, by: SecondOpinion.batchSize) {
                let batch = Array(previews[start..<min(start + SecondOpinion.batchSize, previews.count)])
                let (request, sent) = try SecondOpinion.claudeRequest(batch, apiKey: key)
                library.setOpinions(SecondOpinion.opinions(try await SecondOpinion.claudeVerdicts(request), sent: sent))
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
    /// Opened from an Ask button without a key: says so, and closes once a key is saved so the ask carries on.
    var asking = false
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
                        Text("Optional, and you don't need it: Unhoard finds and cleans everything on its own, for free, on your iPhone. This only adds a label to photos you're unsure about. It never deletes or selects.")
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
                    if asking && !saved {
                        Label("To ask Claude, paste your Anthropic API key here. You'll see exactly what would be sent before anything goes.", systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
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
                            if asking { dismiss() }
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
                    Text("Claude (optional)")
                } footer: {
                    Text("Optional, and not needed to use Unhoard. When you ask Claude, Unhoard first shows the small previews it will send to Anthropic with your key; usage is billed to your Anthropic account. Sensitive and hidden photos are never sent.")
                }
                if !message.isEmpty { Text(message) }
                Section {
                    Link(destination: .rateUnhoard) { Label("Rate on the App Store", systemImage: "star.fill") }
                        .accessibilityIdentifier("rateLink")
                }
            }
            .scrollContentBackground(.hidden)
            .background { CleanerBackdrop(tint: .orange, accent: .purple) }
            .navigationTitle("Second Opinion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone") }
        }
    }
}
