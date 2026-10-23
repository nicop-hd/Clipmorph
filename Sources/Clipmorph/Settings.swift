import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private var keyCache: [ProviderKind: String] = [:]

    @Published var provider: ProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    @Published var models: [ProviderKind: String] {
        didSet { defaults.set(Dictionary(uniqueKeysWithValues: models.map { ($0.key.rawValue, $0.value) }), forKey: "models") }
    }
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") }
    }
    @Published var anthropicWorkspaceID: String {
        didSet { defaults.set(anthropicWorkspaceID, forKey: "anthropicWorkspaceID") }
    }
    @Published private(set) var repositoryDocuments: [RepositoryDocument] = []
    @Published var repositoryError: String?
    @Published var isRepositoryDropTargeted = false

    /// Unsaved text in the settings key fields (kept here because the CLT SDK has no SwiftUI macro plugin for @State).
    @Published var keyDrafts: [ProviderKind: String] = [:]

    init() {
        provider = ProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .anthropic
        let stored = defaults.dictionary(forKey: "models") as? [String: String] ?? [:]
        models = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.map { ($0, stored[$0.rawValue] ?? $0.defaultModel) })
        autoPaste = defaults.bool(forKey: "autoPaste")
        anthropicWorkspaceID = defaults.string(forKey: "anthropicWorkspaceID") ?? ""
        checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        for kind in ProviderKind.allCases {
            keyCache[kind] = Keychain.read(account: kind.rawValue)
        }
    }

    func reloadRepository() {
        repositoryDocuments = Repository.load()
    }

    func addRepositoryFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = Repository.contentTypes
        panel.prompt = "Add to Repository"
        guard panel.runModal() == .OK else { return }
        addRepositoryFiles(panel.urls)
    }

    /// Adds files (and supported files inside folders), reporting anything that was skipped.
    func addRepositoryFiles(_ urls: [URL]) {
        let (files, skipped) = Repository.supportedFiles(in: urls)
        do {
            try Repository.add(files)
            if skipped.isEmpty {
                repositoryError = nil
            } else {
                let names = skipped.prefix(3).joined(separator: ", ") + (skipped.count > 3 ? " and \(skipped.count - 3) more" : "")
                repositoryError = "Skipped unsupported files: \(names). Use PDF, Word, RTF, Markdown or plain text."
            }
        } catch {
            repositoryError = error.localizedDescription
        }
        reloadRepository()
    }

    /// Accepts files dragged from Finder onto the repository drop zone.
    func handleRepositoryDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await Self.loadFileURL(provider) { urls.append(url) }
            }
            addRepositoryFiles(urls)
        }
        return true
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL) as URL?)
            }
        }
    }

    func removeRepositoryDocument(_ document: RepositoryDocument) {
        do {
            try Repository.remove(document)
            repositoryError = nil
        } catch {
            repositoryError = error.localizedDescription
        }
        reloadRepository()
    }

    func model(for kind: ProviderKind) -> String {
        let model = models[kind]?.trimmingCharacters(in: .whitespaces) ?? ""
        return model.isEmpty ? kind.defaultModel : model
    }

    func workspaceID(for kind: ProviderKind) -> String? {
        guard kind == .anthropic else { return nil }
        let id = anthropicWorkspaceID.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    func apiKey(for kind: ProviderKind) -> String? {
        guard let key = keyCache[kind], !key.isEmpty else { return nil }
        return key
    }

    func setAPIKey(_ key: String, for kind: ProviderKind) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(account: kind.rawValue)
            keyCache[kind] = nil
        } else {
            Keychain.write(trimmed, account: kind.rawValue)
            keyCache[kind] = trimmed
        }
        objectWillChange.send()
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var height: CGFloat = 640

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Use", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            ForEach(ProviderKind.allCases) { kind in
                Section(kind.displayName) {
                    HStack {
                        SecureField("API key", text: draftBinding(for: kind),
                                    prompt: Text(settings.apiKey(for: kind) == nil ? "Paste your API key" : "Saved — paste to replace"))
                        Button("Save") {
                            settings.setAPIKey(settings.keyDrafts[kind] ?? "", for: kind)
                            settings.keyDrafts[kind] = ""
                        }
                        .disabled((settings.keyDrafts[kind] ?? "").isEmpty)
                        if settings.apiKey(for: kind) != nil {
                            Button("Remove", role: .destructive) { settings.setAPIKey("", for: kind) }
                        }
                    }
                    TextField("Model", text: modelBinding(for: kind), prompt: Text(kind.defaultModel))
                    if kind == .anthropic {
                        TextField("Workspace ID", text: $settings.anthropicWorkspaceID, prompt: Text("Only for keys not scoped to a workspace"))
                    }
                }
            }

            Section("Behavior") {
                Toggle("Paste into the previous app when I press ⏎", isOn: $settings.autoPaste)
                    .onChange(of: settings.autoPaste) { _, enabled in
                        if enabled { _ = Clipboard.canAutoPaste(prompt: true) }
                    }
                Text("Auto-paste needs Accessibility access (System Settings › Privacy & Security › Accessibility). Results are always copied to the clipboard either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            repositorySection

            Section("Updates") {
                HStack {
                    Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                    Spacer()
                    Text("Version \(UpdateService.currentVersion)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recipes") {
                HStack {
                    Text("Add your own recipes in a JSON file.")
                    Spacer()
                    Button("Open Recipes File") {
                        NSWorkspace.shared.open(RecipeStore.ensureCustomFile())
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Fixed height with a scrolling form, so the window fits on small screens.
        .frame(width: 480, height: height)
    }

    private var repositorySection: some View {
        Section("Repository") {
            Text("Documents used by “Reply from my repository”: product sheets, company info, pricing, tone of voice. PDF, Word, RTF, Markdown or plain text.")
                .font(.caption)
                .foregroundStyle(.secondary)

            repositoryDropZone
            ForEach(settings.repositoryDocuments) { document in
                HStack(spacing: 8) {
                    Image(systemName: document.isReadable ? "doc.text" : "exclamationmark.triangle.fill")
                        .foregroundStyle(document.isReadable ? Color.secondary : Color.orange)
                    Text(document.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(document.isReadable ? "≈ \(Self.formatTokens(document.estimatedTokens)) tokens" : "No readable text")
                        .font(.caption)
                        .foregroundStyle(document.isReadable ? Color.secondary : Color.orange)
                    Button {
                        settings.removeRepositoryDocument(document)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Move to Trash")
                }
            }

            HStack {
                let total = settings.repositoryDocuments.filter(\.isReadable).reduce(0) { $0 + $1.estimatedTokens }
                Text(total > 0 ? "Total ≈ \(Self.formatTokens(total)) tokens" : "")
                    .font(.caption)
                    .foregroundStyle(total > 150_000 ? Color.orange : Color.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.open(Repository.ensureFolder())
                }
                Button("Add Files…") { settings.addRepositoryFiles() }
            }

            if let error = settings.repositoryError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("These documents are sent to \(settings.provider.displayName) with every request from a recipe that uses the repository. Larger repositories make replies slower and cost more per request.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryDropZone: some View {
        let targeted = settings.isRepositoryDropTargeted
        let tint = targeted ? Color.accentColor : Color.secondary
        return VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.title2)
            Text(settings.repositoryDocuments.isEmpty ? "Drop files or folders here" : "Drop more files here")
                .font(.callout.weight(.medium))
            Text("or use Add Files…")
                .font(.caption)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(targeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(targeted ? 1 : 0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $settings.isRepositoryDropTargeted) { providers in
            settings.handleRepositoryDrop(providers)
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }

    private static func formatTokens(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }

    private func draftBinding(for kind: ProviderKind) -> Binding<String> {
        Binding(get: { settings.keyDrafts[kind] ?? "" }, set: { settings.keyDrafts[kind] = $0 })
    }

    private func modelBinding(for kind: ProviderKind) -> Binding<String> {
        Binding(get: { settings.models[kind] ?? "" }, set: { settings.models[kind] = $0 })
    }
}
