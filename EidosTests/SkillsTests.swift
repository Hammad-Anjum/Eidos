import XCTest
import SwiftData
@testable import Eidos

/// Unit tests for the pure-data skills. Platform-backed skills (Calendar,
/// Contacts, Reminders) require user permission and system databases, so
/// they're exercised via real-device smoke tests, not here.
@MainActor
final class SkillsTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var knowledgeRepo: KnowledgeRepository!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            KnowledgeEntry.self,
            EmbeddingRecord.self,
            Conversation.self,
            ConversationMessage.self,
            IngestionLog.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        let embeddingService = EmbeddingService()
        let vectorStore = VectorStore()
        let background = KnowledgeBackgroundActor(modelContainer: modelContainer)
        knowledgeRepo = KnowledgeRepository(
            modelContainer: modelContainer,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            backgroundActor: background
        )
    }

    // MARK: - AddNoteSkill

    func testAddNoteSkillInsertsEntry() async {
        let skill = AddNoteSkill(repo: knowledgeRepo)
        let result = await skill.invoke(parameters: [
            "content": AnyCodable("Milk, eggs, bread"),
            "tags": AnyCodable([AnyCodable("groceries")])
        ])
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, "Noted.")
    }

    func testAddNoteSkillRequiresContent() async {
        let skill = AddNoteSkill(repo: knowledgeRepo)
        let result = await skill.invoke(parameters: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("content"))
    }

    func testAddNoteSkillDedupes() async {
        let skill = AddNoteSkill(repo: knowledgeRepo)
        let first = await skill.invoke(parameters: ["content": AnyCodable("Hello world")])
        let second = await skill.invoke(parameters: ["content": AnyCodable("Hello world")])
        XCTAssertEqual(first.content, "Noted.")
        XCTAssertTrue(second.content.contains("skipped"))
    }

    // MARK: - SearchKBSkill

    func testSearchKBSkillReturnsMatches() async throws {
        _ = try await knowledgeRepo.insert(content: "dentist appointment tuesday", source: .note)
        _ = try await knowledgeRepo.insert(content: "grocery list", source: .note)

        let skill = SearchKBSkill(repo: knowledgeRepo)
        let result = await skill.invoke(parameters: ["query": AnyCodable("dentist")])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.lowercased().contains("dentist"))
    }

    func testSearchKBSkillReportsEmpty() async {
        let skill = SearchKBSkill(repo: knowledgeRepo)
        let result = await skill.invoke(parameters: ["query": AnyCodable("nothing here")])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("No matches"))
    }

    func testSearchKBSkillRequiresQuery() async {
        let skill = SearchKBSkill(repo: knowledgeRepo)
        let result = await skill.invoke(parameters: [:])
        XCTAssertTrue(result.isError)
    }

    // MARK: - CreateReminderSkill parameter validation

    func testCreateReminderSkillRejectsMissingTitle() async {
        let skill = CreateReminderSkill(source: CalendarSource())
        let result = await skill.invoke(parameters: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("title"))
    }

    // MARK: - CalendarSkill / RemindersSkill behavior without permission

    /// Without permission these return empty results gracefully rather
    /// than crashing — the user just sees "No events".
    func testCalendarSkillWithoutPermissionReturnsEmpty() async {
        let skill = CalendarSkill(source: CalendarSource())
        let result = await skill.invoke(parameters: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("No events"))
    }

    func testRemindersSkillWithoutPermissionReturnsEmpty() async {
        let skill = RemindersSkill(source: CalendarSource())
        let result = await skill.invoke(parameters: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("No incomplete"))
    }

    func testContactsSkillRequiresQuery() async {
        let skill = ContactsSkill(source: ContactsSource())
        let result = await skill.invoke(parameters: [:])
        XCTAssertTrue(result.isError)
    }
}
