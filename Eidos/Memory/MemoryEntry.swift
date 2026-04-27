import Foundation

/// Retention priority. Lower raw values are stickier.
/// P1 is loaded on every turn; P5 is next on the eviction queue.
enum MemoryPriority: Int, Sendable, Codable, CaseIterable {
    case p1 = 1  // core identity — never auto-evict
    case p2 = 2  // active priorities — loaded this week
    case p3 = 3  // warm topic knowledge — default
    case p4 = 4  // cooling — archive candidate
    case p5 = 5  // cold — next eviction

    /// Days of inactivity before this priority becomes eligible to decay
    /// to the next tier. Returns `.infinity` for P1.
    var staleAfterDays: Double {
        switch self {
        case .p1: .infinity
        case .p2: 14
        case .p3: 60
        case .p4: 180
        case .p5: 365
        }
    }
}

/// Storage tier. Determines which subdirectory the `.md` file lives in
/// and how the entry is loaded into the prompt context.
enum MemoryTier: String, Sendable, Codable, CaseIterable {
    case coreIdentity     = "core_identity"
    case activePriorities = "active_priorities"
    case topic            = "topic"
    case recentSession    = "recent_session"
    case archive          = "archive"
}

/// A single memory record, persisted as one Markdown file with YAML
/// frontmatter. Plain struct (not `@Model`) because the on-disk `.md`
/// form IS the storage — SwiftData duplicates would just fall out of sync.
struct MemoryEntry: Sendable, Identifiable, Equatable {
    let id: UUID
    var tier: MemoryTier
    var title: String
    var body: String          // Markdown body, excludes the frontmatter block
    var priority: MemoryPriority
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var lastAccessedAt: Date
    /// User-pinned memories are exempt from `MemoryDecayEngine` priority
    /// demotion and archival. The retention contract is: "I told Eidos
    /// to keep this forever, and Eidos has to honor it." Decay still
    /// updates `lastAccessedAt` on access, but never demotes priority
    /// or moves the entry to the archive tier.
    var pinned: Bool

    init(
        id: UUID = UUID(),
        tier: MemoryTier,
        title: String,
        body: String,
        priority: MemoryPriority = .p3,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastAccessedAt: Date? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.tier = tier
        self.title = title
        self.body = body
        self.priority = priority
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastAccessedAt = lastAccessedAt ?? createdAt
        self.pinned = pinned
    }
}
