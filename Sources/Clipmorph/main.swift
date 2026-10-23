import AppKit

MainActor.assumeIsolated {
    // `Clipmorph --selftest [recipe-id] [text]` streams one transform to stdout using the saved settings.
    if let flag = CommandLine.arguments.firstIndex(of: "--selftest") {
        SelfTest.run(arguments: Array(CommandLine.arguments.dropFirst(flag + 1)))
    }

    // `Clipmorph --snapshot <dir>` renders the panel in a few states to PNG files.
    if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
        Snapshot.run(directory: CommandLine.arguments.dropFirst(flag + 1).first ?? ".")
    }

    // `Clipmorph --update [--install]` checks GitHub for a newer release and optionally installs it.
    if let flag = CommandLine.arguments.firstIndex(of: "--update") {
        UpdateCLI.run(install: CommandLine.arguments.dropFirst(flag + 1).contains("--install"))
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

@MainActor
enum SelfTest {
    static func run(arguments: [String]) -> Never {
        let settings = SettingsStore()
        let recipes = RecipeStore.load()
        let recipe = recipes.first { $0.id == arguments.first } ?? recipes[0]
        let input = arguments.dropFirst().joined(separator: " ").isEmpty
            ? "i has went to the store yesterday and buyed three apple's"
            : arguments.dropFirst().joined(separator: " ")
        let provider = settings.provider

        guard let apiKey = settings.apiKey(for: provider) else {
            print("No \(provider.displayName) API key saved.")
            exit(1)
        }
        print("[\(provider.displayName) · \(settings.model(for: provider)) · \(recipe.name)]")
        print("input:  \(input)")
        print("output: ", terminator: "")

        let request = TransformRequest(provider: provider, apiKey: apiKey, model: settings.model(for: provider),
                                       system: Prompts.system(for: recipe), input: input,
                                       workspaceID: settings.workspaceID(for: provider))
        Task {
            do {
                var chunks = 0
                for try await chunk in LLMClient.stream(request) {
                    chunks += 1
                    print(chunk, terminator: "")
                    fflush(stdout)
                }
                print("\n[ok: \(chunks) chunks]")
                exit(0)
            } catch {
                print("\n[error: \(error.localizedDescription)]")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }
}
