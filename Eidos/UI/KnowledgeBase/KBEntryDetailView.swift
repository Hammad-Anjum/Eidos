import SwiftUI

struct KBEntryDetailView: View {
    let entry: KnowledgeEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.entrySource.rawValue.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.content)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}
