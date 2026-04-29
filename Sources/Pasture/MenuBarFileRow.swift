import SwiftUI
import PastureKit

struct MenuBarFileRow: View {
    let file: MDFile
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.pastureAccent : Color.pastureTextTertiary(colorScheme))
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Color.pastureTextPrimary(colorScheme))
                        .lineLimit(1)
                    if let collection = file.collection {
                        Text(collection)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                    }
                }

                Spacer()

                Text(TokenEstimator.formatted(file.tokens))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.pastureTokenBadge)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(isSelected ? Color.pastureSelection(colorScheme) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
