import Foundation

@MainActor
final class TransformModel: ObservableObject {
    enum Phase: Equatable {
        case picking
        case running
        case done
        case failed(String)
    }

    @Published private(set) var input = ""
    @Published private(set) var output = ""
    @Published private(set) var phase: Phase = .picking
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var activeRecipe: Recipe?
    @Published var selection = 0

    let settings: SettingsStore
    private var task: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func reset(input: String) {
        cancel()
        self.input = input
        recipes = RecipeStore.load()
        output = ""
        phase = .picking
        selection = 0
        activeRecipe = nil
    }

    func moveSelection(by delta: Int) {
        guard phase == .picking, !recipes.isEmpty else { return }
        selection = (selection + delta + recipes.count) % recipes.count
    }

    func runSelected() {
        run(at: selection)
    }

    func run(at index: Int) {
        guard recipes.indices.contains(index) else { return }
        selection = index
        run(recipes[index])
    }

    func run(_ recipe: Recipe) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed("The clipboard is empty or doesn't contain text.")
            return
        }
        let provider = settings.provider
        guard let apiKey = settings.apiKey(for: provider) else {
            phase = .failed("No \(provider.displayName) API key yet. Add one in Settings.")
            return
        }

        cancel()
        activeRecipe = recipe
        output = ""
        phase = .running

        let request = TransformRequest(
            provider: provider,
            apiKey: apiKey,
            model: settings.model(for: provider),
            system: Prompts.system(for: recipe),
            input: input,
            workspaceID: settings.workspaceID(for: provider)
        )

        task = Task {
            do {
                for try await chunk in LLMClient.stream(request) {
                    output += chunk
                }
                output = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else {
                    phase = .failed("The model returned an empty response.")
                    return
                }
                Clipboard.write(output)
                phase = .done
            } catch {
                if Task.isCancelled { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func backToRecipes() {
        cancel()
        output = ""
        activeRecipe = nil
        phase = .picking
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
