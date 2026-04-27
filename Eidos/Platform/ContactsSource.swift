import Foundation
import Contacts

struct Contact: Sendable, Identifiable {
    let id: String
    let displayName: String
    let emails: [String]
    let phones: [String]
    let organization: String?

    var searchableText: String {
        ([displayName, organization ?? ""] + emails + phones)
            .joined(separator: " ")
            .lowercased()
    }
}

/// `CNContactStore` wrapper. Serializes through an actor because the
/// store is not marked Sendable and concurrent reads can deadlock.
actor ContactsSource {

    private let store = CNContactStore()
    private(set) var hasPermission = false

    init() {}

    /// B2 (plan.md): original spec used `(try? await ...) != nil` which
    /// returned `true` on denial. Corrected here — explicit bool.
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

    /// Case-insensitive substring match across display name, email, and
    /// phone. Returns the top `limit` matches sorted by display name.
    func search(query: String, limit: Int = 10) async -> [Contact] {
        guard hasPermission else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        let keys: [any CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var matches: [Contact] = []

        do {
            try store.enumerateContacts(with: request) { cn, stop in
                let c = Self.convert(cn)
                if c.searchableText.contains(trimmed) {
                    matches.append(c)
                    if matches.count >= limit { stop.pointee = true }
                }
            }
        } catch {
            return []
        }
        return matches.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Conversion

    private static func convert(_ cn: CNContact) -> Contact {
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        let name = formatter.string(from: cn)
            ?? [cn.givenName, cn.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let emails = cn.emailAddresses.map { $0.value as String }
        let phones = cn.phoneNumbers.map { $0.value.stringValue }
        let org = cn.organizationName.isEmpty ? nil : cn.organizationName
        return Contact(
            id: cn.identifier,
            displayName: name.isEmpty ? "(no name)" : name,
            emails: emails,
            phones: phones,
            organization: org
        )
    }
}
