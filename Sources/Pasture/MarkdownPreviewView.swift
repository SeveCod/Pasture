import SwiftUI

struct MarkdownPreviewView: View {
    let file: MDFile
    @Environment(\.colorScheme) private var colorScheme
    @State private var rendered: (content: String, attributed: AttributedString)?

    var body: some View {
        let effective: AttributedString? = rendered?.content == file.content ? rendered?.attributed : nil
        ScrollView {
            Group {
                if let effective {
                    Text(effective)
                } else {
                    Text(file.content)
                }
            }
            .textSelection(.enabled)
            .font(.pastureEditor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PastureLayout.editorPadding)
        }
        .background(Color.pastureEditor(colorScheme))
        .task(id: file.content) {
            let content = file.content
            if let attributed = try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .full)
            ) {
                rendered = (content, attributed)
            } else {
                rendered = nil
            }
        }
    }
}
