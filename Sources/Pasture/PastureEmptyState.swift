import SwiftUI
import PastureKit

struct PastureEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: PastureLayout.emptyStateSpacing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: PastureLayout.emptyStateIconSize))
                .foregroundStyle(LinearGradient.pastureBrand)
                .rotationEffect(.degrees(-15))
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Circle().fill(Color.pastureGrassDark).frame(width: 4, height: 4)
                Circle().fill(Color.pastureGrassMedium).frame(width: 4, height: 4)
                Circle().fill(Color.pastureGrassOrange).frame(width: 4, height: 4)
            }
            .padding(.bottom, 4)

            Text("Feed your AI")
                .font(.pastureEmptyHeading)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            Text("Select a file or paste content from the clipboard")
                .font(.pastureEmptySubtext)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            Text("Use {{VARIABLE}} or {{VAR=default}} for templates")
                .font(.pastureEmptyHint)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pastureEditor(colorScheme))
    }
}

struct FeedbackToast: View {
    let message: String
    var isError: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.pastureError(colorScheme) : Color.pastureSuccess)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.pastureTextPrimary(colorScheme))
        }
        .padding(.horizontal, PastureLayout.toastHPadding)
        .padding(.vertical, PastureLayout.toastVPadding)
        .background(.regularMaterial, in: Capsule())
        .pastureShadow(PastureEffects.shadowFloat)
        .padding(.bottom, PastureLayout.toastBottomOffset)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
