import SwiftUI

struct NameInputSheet: View {
    let title: String
    let actionLabel: String
    let onConfirm: (String) -> Void

    @State private var fileName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: PastureLayout.sheetSpacing) {
            Text(title)
                .font(.pastureSheetHeading)
            TextField("File name", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { submit() }
            HStack(spacing: PastureLayout.sheetButtonSpacing) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(fileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(PastureLayout.sheetPadding)
        .frame(minWidth: PastureLayout.sheetMinWidth)
    }

    private func submit() {
        let name = fileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onConfirm(name)
        dismiss()
    }
}
