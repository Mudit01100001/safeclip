import SwiftUI

/// Displays a bundled .md file (TERMS or PRIVACY) in a scrollable sheet.
struct LegalDocumentSheet: View {
    let resourceName: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var content: AttributedString = AttributedString("Loading…")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                Text(content)
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 500)
        .onAppear(perform: loadContent)
    }

    private func loadContent() {
        guard
            let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
            let raw = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? AttributedString(
                markdown: raw,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
        else {
            content = AttributedString(
                "Unable to load document. View it online at github.com/Mudit01100001/safeclip"
            )
            return
        }
        content = parsed
    }
}
