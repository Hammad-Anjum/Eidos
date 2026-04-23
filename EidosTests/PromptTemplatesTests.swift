import XCTest
@testable import Eidos

final class PromptTemplatesTests: XCTestCase {

    // MARK: - Shape

    func testFirstMessageIsSystem() {
        let msgs = PromptTemplates.chat(history: [], userMessage: "hi")
        XCTAssertEqual(msgs.first?["role"], "system")
        XCTAssertTrue(msgs.first?["content"]?.contains("Eidos") ?? false)
    }

    func testLastMessageIsUser() {
        let msgs = PromptTemplates.chat(history: [], userMessage: "book me a flight")
        XCTAssertEqual(msgs.last?["role"], "user")
        XCTAssertEqual(msgs.last?["content"], "book me a flight")
    }

    func testEmptyHistoryProducesSystemPlusUser() {
        let msgs = PromptTemplates.chat(history: [], userMessage: "ping")
        XCTAssertEqual(msgs.count, 2)
    }

    // MARK: - Role normalization

    func testAssistantRoleIsRewrittenToModel() {
        // Gemma's chat template expects `model`, not `assistant`.
        let msgs = PromptTemplates.chat(
            history: [(role: "assistant", content: "hi back")],
            userMessage: "ok"
        )
        XCTAssertEqual(msgs[1]["role"], "model")
        XCTAssertEqual(msgs[1]["content"], "hi back")
    }

    func testUserRoleIsPreserved() {
        let msgs = PromptTemplates.chat(
            history: [(role: "user", content: "earlier question")],
            userMessage: "follow-up"
        )
        XCTAssertEqual(msgs[1]["role"], "user")
        XCTAssertEqual(msgs[1]["content"], "earlier question")
    }

    func testHistoryOrderIsPreserved() {
        let msgs = PromptTemplates.chat(
            history: [
                (role: "user", content: "A"),
                (role: "assistant", content: "B"),
                (role: "user", content: "C"),
            ],
            userMessage: "D"
        )
        XCTAssertEqual(msgs.count, 5)  // system + 3 history + current user
        XCTAssertEqual(msgs[1]["content"], "A")
        XCTAssertEqual(msgs[2]["content"], "B")
        XCTAssertEqual(msgs[3]["content"], "C")
        XCTAssertEqual(msgs[4]["content"], "D")
    }

    // MARK: - Augmentation

    func testRetrievedContextAppendsToSystem() {
        let msgs = PromptTemplates.chat(
            history: [],
            userMessage: "q",
            retrievedContext: "User likes pizza."
        )
        let system = msgs[0]["content"] ?? ""
        XCTAssertTrue(system.contains("User likes pizza."))
        XCTAssertTrue(system.contains("Relevant context:"))
    }

    func testEmptyRetrievedContextDoesNotAddHeader() {
        let msgs = PromptTemplates.chat(history: [], userMessage: "q")
        let system = msgs[0]["content"] ?? ""
        XCTAssertFalse(system.contains("Relevant context:"))
    }

    func testToolSchemasAppendToSystem() {
        let msgs = PromptTemplates.chat(
            history: [],
            userMessage: "q",
            toolSchemasJSON: #"[{"name":"search"}]"#
        )
        let system = msgs[0]["content"] ?? ""
        XCTAssertTrue(system.contains("Available tools:"))
        XCTAssertTrue(system.contains(#"{"name":"search"}"#))
    }

    func testBothContextAndToolsAppendInOrder() {
        let msgs = PromptTemplates.chat(
            history: [],
            userMessage: "q",
            retrievedContext: "CTX",
            toolSchemasJSON: "TOOLS"
        )
        let system = msgs[0]["content"] ?? ""
        let ctxRange = system.range(of: "CTX")
        let toolsRange = system.range(of: "TOOLS")
        XCTAssertNotNil(ctxRange)
        XCTAssertNotNil(toolsRange)
        if let ctxRange, let toolsRange {
            XCTAssertLessThan(ctxRange.lowerBound, toolsRange.lowerBound,
                              "Retrieved context should precede tool schemas in the prompt.")
        }
    }

    // MARK: - Keys

    func testEveryMessageHasRoleAndContent() {
        let msgs = PromptTemplates.chat(
            history: [(role: "user", content: "a"), (role: "assistant", content: "b")],
            userMessage: "c"
        )
        for m in msgs {
            XCTAssertNotNil(m["role"])
            XCTAssertNotNil(m["content"])
            XCTAssertEqual(m.count, 2)
        }
    }
}
