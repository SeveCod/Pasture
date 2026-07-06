import SwiftUI
import PastureKit

/// v1.8 Memory Inbox — bandeja de revisión de propuestas del agente MCP. Cada
/// propuesta se aprueba o rechaza individualmente (NO hay "aprobar todo"): la
/// promoción al vault es una decisión humana explícita. Para un `.append` se
/// muestra el diff (contenido actual del destino + líneas propuestas resaltadas).
struct ReviewInboxSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fm: MDFileManager

    /// Propuesta cuyo destino cambió desde que se propuso: pide confirmación.
    @State private var mismatchProposal: Proposal?
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review inbox")
                    .font(.pastureSheetHeading)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()

            if fm.pendingProposals.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(fm.pendingProposals) { proposal in
                            proposalCard(proposal)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 460)
        .alert("The destination changed since this was proposed",
               isPresented: Binding(
                   get: { mismatchProposal != nil },
                   set: { if !$0 { mismatchProposal = nil } }
               ),
               presenting: mismatchProposal) { proposal in
            Button("Append anyway", role: .destructive) {
                apply(proposal, overrideChangedTarget: true)
            }
            Button("Cancel", role: .cancel) { mismatchProposal = nil }
        } message: { _ in
            Text("The file was edited after the proposal was made. The diff above shows the current content. Append to it anyway?")
        }
        .alert("Could not apply proposal",
               isPresented: Binding(
                   get: { errorMessage != nil },
                   set: { if !$0 { errorMessage = nil } }
               ),
               presenting: errorMessage) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Text("No proposals to review.")
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private func proposalCard(_ proposal: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cabecera: destino + tipo.
            HStack(spacing: 6) {
                Image(systemName: proposal.kind == .note ? "doc.badge.plus" : "arrow.down.doc")
                    .foregroundStyle(Color.pastureAccent(colorScheme))
                Text(destinationLabel(proposal))
                    .fontWeight(.medium)
                Spacer()
                Text(proposal.kind == .note ? "new note" : "append")
                    .font(.pastureStatusBar)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }

            // Procedencia.
            Text("proposed by \(proposal.proposedBy) · \(Self.dateFormatter.string(from: proposal.createdAt))")
                .font(.caption)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            // Aviso de secretos (no bloquea).
            if let summary = proposal.secretSummary {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.pastureAmber)
                    Text("Possible secrets: \(summary)")
                        .font(.caption)
                        .foregroundStyle(Color.pastureAmber)
                }
            }

            contentPreview(proposal)

            HStack {
                Spacer()
                Button("Reject", role: .destructive) { fm.reject(proposal) }
                    .controlSize(.small)
                Button("Approve") { apply(proposal, overrideChangedTarget: false) }
                    .controlSize(.small)
                    .keyboardShortcut(.none)
            }
        }
        .padding(12)
        .background(Color.pastureDivider(colorScheme).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Límite de caracteres del contenido ACTUAL del destino mostrado en el diff.
    /// El payload ya está acotado (`maxProposalBytes`), pero el destino de un
    /// `.append` podría ser grande — se recorta la vista previa para no colgar el
    /// sheet materializando megabytes de texto.
    private static let maxPreviewChars = 20_000

    /// Para `.note`, el contenido propuesto. Para `.append`, el contenido ACTUAL
    /// del destino (contexto, recortado) más el bloque propuesto resaltado en
    /// verde — el diff refleja el estado actual del fichero.
    @ViewBuilder
    private func contentPreview(_ proposal: Proposal) -> some View {
        let payload = fm.proposalPayload(proposal) ?? "(payload missing)"
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if proposal.kind == .append, let current = fm.appendTargetContent(proposal) {
                    Text(truncated(current))
                        .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                    Text(payload)
                        .foregroundStyle(Color.pastureSuccess(colorScheme))
                } else {
                    Text(payload)
                        .foregroundStyle(Color.pastureTextPrimary(colorScheme))
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
    }

    private func truncated(_ text: String) -> String {
        text.count > Self.maxPreviewChars
            ? String(text.prefix(Self.maxPreviewChars)) + "\n… (truncated)"
            : text
    }

    private func destinationLabel(_ proposal: Proposal) -> String {
        switch proposal.kind {
        case .note:
            if let collection = proposal.collection, !collection.isEmpty {
                return "\(collection)/\(proposal.filename ?? "")"
            }
            return proposal.filename ?? "(unnamed)"
        case .append:
            return proposal.relativePath ?? "(unknown path)"
        }
    }

    private func apply(_ proposal: Proposal, overrideChangedTarget: Bool) {
        switch fm.promote(proposal, overrideChangedTarget: overrideChangedTarget) {
        case .success:
            break   // la lista se refresca vía @Published pendingProposals
        case .failure(.hashMismatch):
            mismatchProposal = proposal
        case .failure(let error):
            errorMessage = message(for: error)
        }
    }

    private func message(for error: ProposalPromoter.PromoteError) -> String {
        switch error {
        case .outsideVault:   return "The destination is outside the vault."
        case .payloadMissing: return "The proposal's content is missing."
        case .targetMissing:  return "The target file no longer exists."
        case .hashMismatch:   return "The destination changed since the proposal was made."
        case .io(let detail): return "Write failed: \(detail)"
        }
    }
}
