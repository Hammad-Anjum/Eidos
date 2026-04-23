import XCTest
@testable import Eidos

/// Pure-parsing tests for the ingestion importers. Repository integration
/// (insert / dedup) is covered by the existing `KnowledgeRepository` tests.
final class ImporterTests: XCTestCase {

    // MARK: - WhatsApp — US format

    func testParsesUSBracketFormat() {
        let raw = """
        [12/31/23, 11:45:00 PM] Alice: Happy new year!
        [1/1/24, 12:05:13 AM] Bob: 🎉 You too
        """
        let messages = WhatsAppImporter.parse(raw)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].sender, "Alice")
        XCTAssertEqual(messages[0].content, "Happy new year!")
        XCTAssertEqual(messages[1].sender, "Bob")
        XCTAssertEqual(messages[1].content, "🎉 You too")
        XCTAssertNotNil(messages[0].timestamp)
    }

    // MARK: - WhatsApp — EU dash format

    func testParsesEUDashFormat() {
        let raw = """
        31/12/2023, 23:45 - Alice: Happy new year!
        01/01/2024, 00:05 - Bob: You too
        """
        let messages = WhatsAppImporter.parse(raw)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].sender, "Alice")
        XCTAssertEqual(messages[1].sender, "Bob")
    }

    // MARK: - WhatsApp — continuation lines

    func testMergesContinuationLines() {
        let raw = """
        [12/31/23, 11:45:00 PM] Alice: Line one
        Line two, same message
        [1/1/24, 12:05:13 AM] Bob: Reply
        """
        let messages = WhatsAppImporter.parse(raw)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0].content.contains("Line one"))
        XCTAssertTrue(messages[0].content.contains("Line two"))
    }

    // MARK: - WhatsApp — garbage lines

    func testIgnoresUnparseableLeadingLines() {
        // WhatsApp exports sometimes begin with an encryption notice that
        // doesn't match the header pattern. Our parser should just drop it.
        let raw = """
        Messages to this chat and calls are now secured with end-to-end encryption.
        [12/31/23, 11:45:00 PM] Alice: Real message
        """
        let messages = WhatsAppImporter.parse(raw)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].sender, "Alice")
    }

    // MARK: - WhatsApp — invisible marks

    func testStripsLTRMarks() {
        let raw = "\u{200E}[12/31/23, 11:45:00 PM] Alice: Hi"
        let messages = WhatsAppImporter.parse(raw)
        XCTAssertEqual(messages.count, 1)
    }

    // MARK: - Mbox splitting

    func testMboxSplitsOnFromPrefix() {
        let mbox = """
        From foo@bar.com Mon Jan 1 00:00:00 2024
        Subject: one
        From: a@b.com

        body one

        From bar@baz.com Mon Jan 2 00:00:00 2024
        Subject: two
        From: c@d.com

        body two
        """
        let messages = MailImporter.split(mbox)
        XCTAssertEqual(messages.count, 2)
    }

    func testMboxExtractsHeadersAndBody() {
        let single = """
        From foo@bar.com Mon Jan 1 00:00:00 2024
        Subject: Meeting tomorrow
        From: alice@example.com
        Date: Mon, 1 Jan 2024 10:00:00 +0000

        Let's meet at 3pm.
        """
        guard let parsed = MailImporter.extractReadable(single) else {
            return XCTFail("Expected parsed mail")
        }
        XCTAssertEqual(parsed.subject, "Meeting tomorrow")
        XCTAssertEqual(parsed.from, "alice@example.com")
        XCTAssertTrue(parsed.body.contains("3pm"))
    }
}
