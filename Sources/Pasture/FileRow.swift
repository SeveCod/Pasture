import SwiftUI
import PastureKit

struct FileRow: View {
    let file: MDFile
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PastureLayout.fileRowInternalSpacing) {
                HStack(spacing: PastureLayout.fileRowIconSpacing) {
                    Text(file.name)
                        .font(.pastureFileName)
                        .foregroundStyle(Color.pastureTextPrimary(colorScheme))
                        .lineLimit(1)
                    if file.hasTemplateVars {
                        TemplateBadge(compact: true, colorScheme: colorScheme)
                    }
                    if case .expired = file.freshness(now: Date()) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.pastureAmber)
                            .help("Stale — past its review date")
                            .accessibilityLabel("Stale note, past its review date")
                    }
                }
                Text(file.modifiedDate, style: .relative)
                    .font(.pastureFileDate)
                    .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            }
            Spacer()
            Text(TokenEstimator.formatted(file.tokens))
                .font(.pastureTokenCount)
                .foregroundStyle(Color.pastureTokenBadgeText(colorScheme))
                .padding(.horizontal, PastureLayout.tokenBadgeHPadding)
                .padding(.vertical, PastureLayout.tokenBadgeVPadding)
                .background(
                    Color.pastureTokenBadgeBg(colorScheme),
                    in: RoundedRectangle(cornerRadius: PastureEffects.cornerRadiusSmall)
                )
        }
        .padding(.vertical, PastureLayout.fileRowVerticalPadding)
    }
}
