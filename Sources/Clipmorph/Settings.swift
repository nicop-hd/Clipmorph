import AppKit
import SwiftUI

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
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Repository.contentTypes
        panel.prompt = "Add to Repository"
        guard panel.runModal() == .OK else { return }
        do {
            try Repository.add(panel.urls)
            repositoryError = nil
        } catch {
            repositoryError = error.localizedDescription
        }
        reloadRepository()
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
        .frame(width: 480, height: 640)
    }

    private var repositorySection: some View {
        Section("Repository") {
            Text("Documents used by “Reply from my repository”: product sheets, company info, pricing, tone of voice. PDF, Word, RTF, Markdown or plain text.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.repositoryDocuments.isEmpty {
                Text("No documents yet.")
                    .foregroundStyle(.secondary)
            }
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
