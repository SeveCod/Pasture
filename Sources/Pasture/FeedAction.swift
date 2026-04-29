import SwiftUI
import AppKit
import PastureKit

struct FeedButton: View {
    let targets: [MDFile]
    let totalTokens: Int
    let destinations: [ExportDestination]
    let onClipboard: () -> Void
    let onExport: (ExportDestination) -> Void
    @State private var hover = false

    var body: some View {
        let isDisabled = targets.isEmpty

        if destinations.isEmpty {
            Button(action: onClipboard) {
                buttonLabel(isDisabled: isDisabled)
            }
            .buttonStyle(.plain)
            .onHover { hovering in hover = hovering }
            .disabled(isDisabled)
            .help("Copy wrapped in <context> tags for Claude")
        } else {
            Menu {
                Button("Copy to Clipboard") { onClipboard() }
                Divider()
                ForEach(destinations) { dest in
                    Button("Export to \(dest.name)") { onExport(dest) }
                }
            } label: {
                buttonLabel(isDisabled: isDisabled)
            } primaryAction: {
                if let defaultID = ExportSettings.defaultDestinationID(),
                   let dest = destinations.first(where: { $0.id == defaultID }) {
                    onExport(dest)
                } else {
                    onClipboard()
                }
            }
            .menuStyle(.borderlessButton)
            .onHover { hovering in hover = hovering }
            .disabled(isDisabled)
            .help("Feed: click for default, hold for options")
        }
    }

    @ViewBuilder
    private func buttonLabel(isDisabled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill")
                .rotationEffect(.degrees(15))
            Text("Feed \(TokenEstimator.formatted(totalTokens))")
                .font(.pastureToolbarLabel)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, PastureLayout.feedButtonHPadding)
        .padding(.vertical, PastureLayout.feedButtonVPadding)
        .background(
            isDisabled
                ? AnyShapeStyle(Color.pastureTextTertiaryLight.opacity(0.3))
                : AnyShapeStyle(hover ? LinearGradient.pastureFeedButtonHover : LinearGradient.pastureFeedButton)
        )
        .clipShape(RoundedRectangle(cornerRadius: PastureLayout.feedButtonRadius))
        .scaleEffect(hover && !isDisabled ? 1.02 : 1.0)
        .animation(.easeInOut(duration: PastureEffects.animationQuick), value: hover)
    }
}

struct TemplateSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var variables: [TemplateVariable]
    let totalTokens: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: PastureLayout.sheetSpacing) {
            Text("Fill template variables")
                .font(.pastureSheetHeading)
            Text("These placeholders will be replaced before copying")
                .font(.pastureSheetSubheading)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($variables) { $variable in
                        HStack(alignment: .top) {
                            Text("{{\(variable.name)}}")
                                .font(.pastureTemplateVar)
                                .foregroundStyle(Color.pastureTemplate)
                                .frame(width: PastureLayout.templateVarLabelWidth, alignment: .trailing)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 2) {
                                TextField(
                                    variable.kind == .list
                                        ? "item1, item2, item3"
                                        : (variable.defaultValue.isEmpty ? "Value" : variable.defaultValue),
                                    text: $variable.value
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: PastureLayout.templateVarInputWidth)

                                if variable.kind == .list && !variable.value.isEmpty {
                                    Text("\(variable.listItems.count) items")
                                        .font(.caption2)
                                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Text("~\(TokenEstimator.formatted(totalTokens)) tokens")
                .font(.pastureTokenBadge)
                .foregroundStyle(Color.pastureTokenBadge)

            HStack(spacing: PastureLayout.sheetButtonSpacing) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(action: onConfirm) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11))
                        Text("Feed")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(LinearGradient.pastureFeedButton)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PastureLayout.sheetPadding)
        .frame(minWidth: PastureLayout.templateSheetMinWidth)
    }
}
