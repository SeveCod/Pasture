import SwiftUI
import PastureKit

/// Memoria viva (v1.7, Fase A) — cola de revisión: agrupa las notas caducadas y
/// permite marcar cada una como revisada (escribe `last_reviewed: hoy` vía
/// `MDFileManager.markReviewed`, que usa el `FrontmatterWriter` puro y testeado).
struct ReviewQueueSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fm: MDFileManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review queue")
                    .font(.pastureSheetHeading)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()

            let stale = fm.staleFiles()
            if stale.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.pastureSuccess(colorScheme))
                    Text("Everything is fresh.")
                        .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List(stale) { file in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).fontWeight(.medium)
                            Text(staleDetail(file))
                                .font(.caption)
                                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                        }
                        Spacer()
                        Button("Mark reviewed") { fm.markReviewed(file) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func staleDetail(_ file: MDFile) -> String {
        if case .expired(let days) = file.freshness(now: Date()) {
            return "stale — \(days) day\(days == 1 ? "" : "s") since last review"
        }
        return ""
    }
}
