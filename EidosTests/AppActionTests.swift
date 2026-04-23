import XCTest
@testable import Eidos

@MainActor
final class AppActionTests: XCTestCase {

    // MARK: - URL construction

    func testWhatsAppURL() {
        let action = AppAction.whatsapp(phone: "+1 (415) 555-1212", text: "Hello, world!")
        let url = action.url
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "whatsapp")
        // Phone should be cleaned (digits + leading +).
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "phone" })?.value, "+14155551212")
        XCTAssertEqual(items.first(where: { $0.name == "text" })?.value, "Hello, world!")
    }

    func testSMSURL() {
        let action = AppAction.sms(phone: "+14155551212", body: "hi")
        XCTAssertEqual(action.url?.scheme, "sms")
    }

    func testEmailURL() {
        let action = AppAction.email(
            to: "alice@example.com",
            subject: "Hi there",
            body: "body text"
        )
        let s = action.url?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("mailto:alice@example.com"))
        XCTAssertTrue(s.contains("subject=Hi%20there"))
    }

    func testEmailURLOmitsEmptyFields() {
        let action = AppAction.email(to: "a@b.com", subject: nil, body: nil)
        let s = action.url?.absoluteString ?? ""
        XCTAssertEqual(s, "mailto:a@b.com")
    }

    func testPhoneCallURL() {
        let action = AppAction.phoneCall(phone: "+1 (415) 555-1212")
        XCTAssertEqual(action.url?.absoluteString, "tel:+14155551212")
    }

    func testMapsURL() {
        let action = AppAction.mapsNavigate(destination: "Ferry Building, SF", transport: .walking)
        let s = action.url?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("maps://"))
        XCTAssertTrue(s.contains("dirflg=w"))
        XCTAssertTrue(s.contains("daddr=Ferry%20Building"))
    }

    func testUberURL() {
        let action = AppAction.rideRequest(destination: "SFO airport")
        let s = action.url?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("uber://"))
        XCTAssertTrue(s.contains("action=setPickup"))
    }

    // MARK: - Display

    func testPhoneMasking() {
        XCTAssertEqual(AppAction.maskPhone("+14155551212"), "••••1212")
        XCTAssertEqual(AppAction.maskPhone("123"), "123")  // too short to mask
    }

    func testConfirmationTitle() {
        let action = AppAction.whatsapp(phone: "+14155551212", text: "hi")
        XCTAssertTrue(action.confirmationTitle.contains("••••1212"))
    }

    // MARK: - Registry

    func testEnqueueAndDismiss() {
        let registry = AppActionRegistry()
        let a = AppAction.phoneCall(phone: "+14155551212")
        registry.enqueue(a)
        XCTAssertEqual(registry.pending, [a])
        registry.dismiss(a)
        XCTAssertTrue(registry.pending.isEmpty)
    }

    func testEquatableDistinguishesActions() {
        XCTAssertNotEqual(
            AppAction.phoneCall(phone: "+1"),
            AppAction.phoneCall(phone: "+2")
        )
    }
}
