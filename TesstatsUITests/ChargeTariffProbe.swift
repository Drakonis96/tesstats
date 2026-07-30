import XCTest

/// TEMPORARY probe for the charge cost editor and the tariff plan editor. Deleted before commit.
@MainActor
final class ChargeTariffProbe: XCTestCase {
    private func launch(_ tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TESSTATS_DEMO"] = "1"
        app.launchEnvironment["TESSTATS_SKIP_TUTORIAL"] = "1"
        app.launchEnvironment["TESSTATS_TAB"] = tab
        let hex = #"{"languageCode":"en","demoMode":true}"#.utf8.map { String(format: "%02x", $0) }.joined()
        app.launchArguments = ["-AppleLanguages", "(en)", "-tesstats.serverconfig", "<\(hex)>"]
        app.launch()
        return app
    }

    private func dump(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1.2)
        print("PROBE-\(name)-BEGIN")
        for t in app.staticTexts.allElementsBoundByIndex.map(\.label) where !t.isEmpty { print("  | \(t)") }
        print("  -- buttons: \(app.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.prefix(14))")
        print("PROBE-\(name)-END")
    }

    func testChargeDetailExposesEditablePrice() {
        let app = launch("charging")
        XCTAssertTrue(app.staticTexts["Charging"].firstMatch.waitForExistence(timeout: 12))
        app.swipeUp(); app.swipeUp()
        Thread.sleep(forTimeInterval: 1.0)

        // Open the first session in the list.
        let home = app.staticTexts.matching(NSPredicate(format: "label == 'Home'")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        Thread.sleep(forTimeInterval: 1.5)
        dump("CHARGE-DETAIL", app)

        XCTAssertTrue(app.staticTexts["Cost"].firstMatch.exists, "cost card missing")
        let editButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'price per kWh'")).firstMatch
        XCTAssertTrue(editButton.exists, "no price editing affordance on the charge detail")
        editButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(app.staticTexts["Price per kWh"].waitForExistence(timeout: 4), "price alert did not open")
        dump("PRICE-ALERT", app)

        // Type a price and save, then confirm the cost card reflects it.
        app.typeText("0.42")
        app.buttons["Save"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        dump("AFTER-SAVE", app)
        // This demo session carries a cost recorded by TeslaMate, so the displayed cost must NOT
        // change — what the override does is price this location's uncosted sessions. The stored
        // override shows up as the button flipping to "Edit".
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Edit price per kWh'")).firstMatch.exists,
                      "the per-location price was not stored")
    }

    func testTariffPlanEditorTilesTheDay() {
        let app = launch("summary")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 12))
        app.buttons["Settings"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        app.buttons["Prefs"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)

        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tariff plans'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "no Tariff plans link in Prefs")
        link.tap()
        Thread.sleep(forTimeInterval: 1.2)
        dump("PLANS", app)

        app.buttons["Add plan"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        dump("PLAN-ADDED", app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'New plan'")).firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        dump("PLAN-DETAIL", app)

        app.buttons["Add band"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Add band"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        dump("THREE-BANDS", app)
    }
}
