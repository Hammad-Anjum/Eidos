import Foundation

@MainActor
@Observable
final class HomeViewModel {
    var digest: String = ""
    var isGeneratingDigest = false

    private let digestGenerator: DigestGenerator

    init(digestGenerator: DigestGenerator) {
        self.digestGenerator = digestGenerator
    }

    func refresh() async {
        // TODO(phase 4)
    }
}
