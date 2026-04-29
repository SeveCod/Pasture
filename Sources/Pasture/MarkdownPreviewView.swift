import SwiftUI

struct MarkdownPreviewView: View {
    let file: MDFile
    @Environment(\.colorScheme) private var colorScheme

    private var attributedContent: AttributedString {
        (try? AttributedString(
            markdown: file.content,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(file.content)
    }

    var body: some View {
        ScrollView {
            Text(attributedContent)
                .textSelection(.enabled)
                .font(.pastureEditor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PastureLayout.editorPadding)
        }
        .background(Color.pastureEditor(colorScheme))
    }
}
