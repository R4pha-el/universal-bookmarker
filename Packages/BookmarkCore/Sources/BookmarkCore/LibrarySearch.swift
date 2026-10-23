import Foundation

public enum LibrarySearch {
    public static func matches(_ item: BookmarkItem, query: String) -> Bool {
        guard item.deletedAt == nil else { return false }
        let query = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return true }
        return [item.title, item.url?.absoluteString, item.url?.host, item.filename, item.note]
            .compactMap { $0 }
            .contains { fold($0).contains(query) }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }
}
