import SwiftUI
import Combine

struct EditorView: View {
    @Binding var file: MDFile
    let onSave: () -> Void

    private let saveSubject = PassthroughSubject<Void, Never>()

    var body: some View {
        TextEditor(text: $file.content)
            .font(.pastureEditor)
            .padding(PastureLayout.editorPadding)
            .scrollContentBackground(.hidden)
            .onChange(of: file.content) { _, _ in
                file.updateDerivedProperties()
                saveSubject.send()
            }
            .onReceive(saveSubject.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in
                onSave()
            }
    }
}
