import Foundation
import BookmarkCloud

extension BackendConfiguration {
    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              !rawURL.isEmpty, !key.isEmpty, !rawURL.contains("$("), !key.contains("$("),
              let url = URL(string: rawURL), url.scheme == "https" else { return nil }
        return BackendConfiguration(url: url, publishableKey: key)
    }
}
