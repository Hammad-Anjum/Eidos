import XCTest
@testable import Eidos

final class MemoryCrystallizerTests: XCTestCase {

    private var tempRoot: URL!
    private var manager: MemoryManager!
    private var crystallizer: MemoryCrystallizer!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eidos-crystal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        manager = MemoryManager(rootOverride: tempRoot)
        // GemmaSession is not actually invoked in parse-only tests.
        crystallizer = MemoryCrystallizer(gemma: GemmaSession(), manager: manager)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try await super.tearDown()
    }

    // MARK: - Parser — happy paths

    func testParsesWellFormedJSONArray() async throws {
        let raw = """
        [
          {"title": "Likes sushi", "body": "User prefers sushi at lunch.", "tags": ["food"]}
        ]
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Likes sushi")
        XCTAssertEqual(items[0].tags, ["food"])
    }

    func testIgnoresSurroundingProse() async throws {
        let raw = """
        Here are the memories I extracted:

        [{"title": "t", "body": "b"}]

        Let me know if you need more!
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "t")
    }

    func testIgnoresMarkdownCodeFence() async throws {
        let raw = """
        ```json
        [{"title": "t", "body": "b"}]
        ```
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items.count, 1)
    }

    func testDecodesOptionalTierAndPriority() async throws {
        let raw = """
        [{"title": "t", "body": "b", "tier": "core_identity", "priority": 1}]
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items[0].tier, .coreIdentity)
        XCTAssertEqual(items[0].priority, .p1)
    }

    func testDropsItemsMissingRequiredFields() async throws {
        let raw = """
        [
          {"title": "good", "body": "has both"},
          {"title": "bad: no body"},
          {"body": "bad: no title"},
          {"title": "", "body": "empty title"},
          {"title": "also good", "body": "fine"}
        ]
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.title), ["good", "also good"])
    }

    func testHandlesArrayInsideStringLiteral() async throws {
        // The inner `[` shouldn't confuse the array extractor.
        let raw = """
        [{"title": "arr", "body": "Quote: \\"values are [a, b, c]\\""}]
        """
        let items = try await crystallizer.parse(raw)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].body.contains("[a, b, c]"))
    }

    // MARK: - Parser — error paths

    func testNoArrayThrows() async {
        do {
            _ = try await crystallizer.parse("just prose, no JSON")
            XCTFail("expected malformedResponse")
        } catch MemoryCrystallizerError.malformedResponse {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyArrayReturnsEmpty() async throws {
        let items = try await crystallizer.parse("[]")
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Prompt template

    func testCrystallizationPromptContainsTranscript() {
        let messages = PromptTemplates.crystallization(conversation: [
            (role: "user", content: "I'm going to Paris next Tuesday"),
            (role: "assistant", content: "Have a great trip!")
        ])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[0]["content"]?.contains("JSON array") ?? false)
        XCTAssertTrue(messages[1]["content"]?.contains("Paris next Tuesday") ?? false)
    }
}
