import Foundation
#if canImport(MusicKit)
import MusicKit
#endif

/// Recently-played Apple Music. Apple Music only — Spotify/YouTube
/// Music don't expose iOS APIs. Still useful: our research showed
/// many iOS power users DO use Apple Music, and the recently-played
/// list is a rich ambient signal for digest narration.
///
/// Privacy: we never store song metadata to disk. We fetch on demand
/// when the digest is generated and summarize counts/titles in the
/// narration prompt, then discard.
actor MusicSource {

    private(set) var hasPermission = false

    init() {}

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        #if canImport(MusicKit)
        let status = await MusicAuthorization.request()
        hasPermission = (status == .authorized)
        return hasPermission
        #else
        return false
        #endif
    }

    // MARK: - Recently played

    struct RecentlyPlayed: Sendable {
        var trackCount: Int
        var topTitles: [String]

        var readable: String {
            guard trackCount > 0 else { return "No recent Apple Music." }
            let titles = topTitles.prefix(3).joined(separator: ", ")
            if titles.isEmpty { return "\(trackCount) tracks played recently." }
            return "\(trackCount) tracks — \(titles)"
        }
    }

    /// Fetches up to `limit` recently-played items.
    func recentlyPlayed(limit: Int = 10) async -> RecentlyPlayed {
        #if canImport(MusicKit)
        guard hasPermission else { return .init(trackCount: 0, topTitles: []) }
        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            request.limit = limit
            let response = try await request.response()
            let songs = response.items
            let titles = songs.prefix(5).map { "\($0.title) — \($0.artistName)" }
            return .init(trackCount: songs.count, topTitles: Array(titles))
        } catch {
            return .init(trackCount: 0, topTitles: [])
        }
        #else
        return .init(trackCount: 0, topTitles: [])
        #endif
    }
}
