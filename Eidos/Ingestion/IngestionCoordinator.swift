import Foundation

@MainActor
@Observable
final class IngestionCoordinator {
    var pendingCount = 0
    var isProcessing = false
    var lastResult: String?

    private let repo: KnowledgeRepository

    init(repo: KnowledgeRepository) {
        self.repo = repo
        refresh()
    }

    func refresh() {
        // TODO(phase 5): count items in the App Group pending queue
        pendingCount = 0
    }

    func processAll() async {
        // TODO(phase 5)
    }
}
