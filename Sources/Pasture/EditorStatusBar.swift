import SwiftUI
import PastureKit

struct EditorStatusBar: View {
    let file: MDFile
    let onOpenInEditor: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            Text(file.name + ".md")
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            if let collection = file.collection {
                Text(collection)
                    .font(.pastureStatusBar)
                    .foregroundStyle(Color.pastureTokenBadge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Color.pastureTokenBadgeBg(colorScheme),
                        in: RoundedRectangle(cornerRadius: PastureEffects.cornerRadiusSmall)
                    )
            }

            if file.hasTemplateVars {
                TemplateBadge(compact: false, colorScheme: colorScheme)
            }

            Spacer()

            Button(action: onOpenInEditor) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10))
                    Text("Open in Editor")
                        .font(.pastureStatusBar)
                }
                .foregroundStyle(Color.pastureAccent)
            }
            .buttonStyle(.plain)
            .help("Open in default editor (Cmd+E)")
            .accessibilityLabel("Open in default editor")

            Text("~\(TokenEstimator.formatted(file.tokens)) tokens")
                .font(.pastureTokenCount)
                .foregroundStyle(Color.pastureTokenBadge)
        }
        .padding(.horizontal, PastureLayout.statusBarHPadding)
        .padding(.vertical, PastureLayout.statusBarVPadding)
        .background(Color.pastureStatusBar(colorScheme))
    }
}
