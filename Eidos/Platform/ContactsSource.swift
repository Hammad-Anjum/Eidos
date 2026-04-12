import Foundation
import Contacts

actor ContactsSource {
    private let store = CNContactStore()
    private(set) var hasPermission = false

    init() {}

    // B2: spec had `(try? await ...) != nil` which returned `true` even
    // on user denial. Fixed to explicitly check the boolean return.
    func requestPermission() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            hasPermission = granted
            return granted
        } catch {
            hasPermission = false
            return false
        }
    }

    func search(query: String) async -> [String] {
        // TODO(phase 4)
        []
    }
}
