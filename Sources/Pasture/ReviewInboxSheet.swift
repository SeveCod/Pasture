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
    /// UX-5: rechazar era instantáneo e irreversible (borra el par del `.inbox/`),
    /// mientras borrar un preset sí pedía confirmación. Ahora también confirma.
    @State private var proposalPendingRejection: Proposal?
    /// UX-5: aprobar no daba señal alguna de éxito; aquí va la ruta creada.
    @State private var successMessage: String?

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
                // A11Y-6: Escape cierra la bandeja. Approve/Reject siguen sin
                // atajo (`.none` explícito) para que una tecla no promocione
                // una propuesta sin intención.
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            if let successMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(successMessage)
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(Color.pastureSuccess(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

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
        .alert("Reject proposal?",
               isPresented: Binding(
                   get: { proposalPendingRejection != nil },
                   set: { if !$0 { proposalPendingRejection = nil } }
               ),
               presenting: proposalPendingRejection) { proposal in
            Button("Reject", role: .destructive) {
                fm.reject(proposal)
                proposalPendingRejection = nil
            }
            Button("Cancel", role: .cancel) { proposalPendingRejection = nil }
        } message: { proposal in
            Text("The proposal for '\(destinationLabel(proposal))' will be discarded permanently.")
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
                        .foregroundStyle(Color.pastureWarning(colorScheme))
                    Text("Possible secrets: \(summary)")
                        .font(.caption)
                        .foregroundStyle(Color.pastureWarning(colorScheme))
                }
            }

            contentPreview(proposal)

            HStack {
                Spacer()
                Button("Reject", role: .destructive) { proposalPendingRejection = proposal }
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
                    // A11Y-7: encabezados textuales — el diff no puede depender
                    // solo del color para distinguir lo actual de lo propuesto.
                    Text("Current content")
                        .font(.caption)
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                    Text(truncated(current))
                        .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                    Text("Proposed addition")
                        .font(.caption)
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                    Text(payload)
                        .foregroundStyle(Color.pastureSuccess(colorScheme))
                        .accessibilityLabel("Proposed addition: \(payload)")
                } else {
                    Text(payload)
                        .foregroundStyle(Color.pastureTextPrimary(colorScheme))
                }
            }
            // A11Y-10: relativa pero a `.callout` (12 pt en macOS, el tamaño previo
            // exacto): este diff se lee antes de aprobar una escritura de agente,
            // así que no puede perder legibilidad al hacerse escalable.
            .font(.system(.callout, design: .monospaced))
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
        case .success(let url):
            // La lista se refresca vía @Published pendingProposals; el aviso deja
            // constancia de dónde acabó el contenido (una promoción no es visible
            // de otro modo desde la bandeja).
            let path = PresetResolver.relativePath(for: url, base: MDFileManager.pastureDir)
                ?? url.lastPathComponent
            successMessage = "Promoted to \(path)"
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
