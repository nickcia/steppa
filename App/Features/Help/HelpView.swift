import SwiftUI

/// "How do I…?": every help article, searchable. The coach answers from the same articles.
struct HelpView: View {
    @State private var query = ""

    var body: some View {
        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty ? AppHelp.articles : AppHelp.search(query, limit: 10)
        List {
            if shown.isEmpty {
                Text("Nothing found. Try other words, like “Garmin”, “holiday” or “treadmill”.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
            }
            ForEach(shown) { article in
                NavigationLink {
                    HelpArticleView(article: article)
                } label: {
                    Text(article.title).foregroundStyle(Theme.ink)
                }
            }
        }
        .searchable(text: $query, prompt: "How do I…")
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpArticleView: View {
    let article: HelpArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(article.title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                ForEach(Array(article.body.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    Text(String(line)).font(.body).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
