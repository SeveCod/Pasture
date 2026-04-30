import SwiftUI

struct TemplateBadge: View {
    let compact: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "curlybraces")
                .font(.system(size: compact ? 10 : 9, weight: compact ? .medium : .regular))
            if !compact {
                Text("Template")
                    .font(.system(.caption2, design: .default, weight: .medium))
            }
        }
        .foregroundStyle(Color.pastureTemplate)
        .padding(.horizontal, compact ? 0 : 6)
        .padding(.vertical, compact ? 0 : 2)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: PastureEffects.cornerRadiusSmall)
                    .fill(Color.pastureTemplateBg(colorScheme))
            }
        }
        .accessibilityLabel("Template")
    }
}
