import SwiftUI

struct PanelView: View {
    @ObservedObject var model: TransformModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 580, height: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.input.isEmpty ? "Clipboard is empty" : model.input)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3)
                    .foregroundStyle(model.input.isEmpty ? .secondary : .primary)
                Text("\(model.input.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .picking:
            recipeList
        case .running, .done:
            resultView
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Open Settings", action: openSettings)
            }
            .padding(16)
        }
    }

    private var recipeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.recipes.enumerated()), id: \.element.id) { index, recipe in
                        RecipeRow(index: index, recipe: recipe, isSelected: index == model.selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { model.run(at: index) }
                            .onHover { if $0 { model.selection = index } }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selection) { _, newValue in
                proxy.scrollTo(newValue)
            }
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recipe = model.activeRecipe {
                HStack(spacing: 6) {
                    Image(systemName: recipe.icon)
                    Text(recipe.name).fontWeight(.medium)
                    if model.phase == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .font(.callout)
            }
            ScrollView {
                Text(model.output.isEmpty ? " " : model.output)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            switch model.phase {
            case .picking:
                hint("1–9", "run")
                hint("↑↓ ⏎", "select")
            case .running:
                hint("⌫", "back")
            case .done:
                hint("⏎", model.settings.autoPaste ? "paste" : "close")
                hint("⌫", "back")
            case .failed:
                hint("⌫", "back")
            }
            Spacer()
            hint("esc", "close")
            Text("\(model.settings.provider.displayName) · \(model.settings.model(for: model.settings.provider))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct RecipeRow: View {
    let index: Int
    let recipe: Recipe
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : " ")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Image(systemName: recipe.icon)
                .frame(width: 18)
            Text(recipe.name)
            Spacer()
            if recipe.isCustom {
                Text("custom").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        )
    }
}
