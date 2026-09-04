import SwiftUI
import PastureKit

/// Aparato común del flujo de feed: sheet de plantilla, alert de secretos
/// (SEC-6: Cancel por defecto) y toast de feedback. Compartido por la ventana
/// principal y el popover del menu bar.
struct FeedChrome: ViewModifier {
    @ObservedObject var feedService: FeedService
    let fm: MDFileManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $feedService.showTemplateSheet) {
                TemplateSheet(
                    variables: $feedService.templateVariables,
                    totalTokens: fm.totalTokens(for: feedService.pendingFeedTargets),
                    onCancel: { feedService.cancelTemplateFeed() },
                    onConfirm: { feedService.confirmTemplateFeed(fm: fm) }
                )
            }
            .alert(
                "Possible secret detected",
                isPresented: Binding(
                    get: { feedService.pendingSecretResult != nil },
                    set: { if !$0 { feedService.cancelSecretDialog() } }
                ),
                presenting: feedService.pendingSecretResult
            ) { _ in
                // Default seguro = Cancelar (Enter/Escape). SEC-6.
                Button("Cancel", role: .cancel) { feedService.cancelSecretDialog() }
                Button("Continue anyway", role: .destructive) { feedService.proceedDespiteSecrets() }
            } message: { result in
                // SEC-4: solo fichero + tipo, nunca el valor. SEC-5: "known", sin garantía.
                Text(result.alertMessage)
            }
            .overlay(alignment: .bottom) {
                if let msg = feedService.feedbackMessage {
                    FeedbackToast(message: msg, isError: feedService.feedbackIsError)
                }
            }
            .animation(.easeInOut(duration: PastureEffects.animationStandard), value: feedService.feedbackMessage)
    }
}

extension View {
    func feedChrome(_ feedService: FeedService, fm: MDFileManager) -> some View {
        modifier(FeedChrome(feedService: feedService, fm: fm))
    }
}
