import XCTest

@MainActor
final class TesstatsUITests: XCTestCase {
    func testDemoModeVisualSurfacesAreReachableAndReadOnly() {
        let app = XCUIApplication()
        app.launchEnvironment["TESSTATS_DEMO"] = "1"
        app.launchEnvironment["TESSTATS_SKIP_TUTORIAL"] = "1"
        app.launch()

        XCTAssertTrue(waitForAnyText(["Sample data", "Datos de muestra", "Estos son datos de muestra"], app: app, timeout: 8))
        XCTAssertTrue(anyTextExists(["Efficiency 30d", "Efic. 30d", "Last 48h", "Últimas 48h"], app: app))
        XCTAssertFalse(app.buttons["Unlock"].exists)
        XCTAssertFalse(app.buttons["Start climate"].exists)

        tapTab(["Trips", "Viajes"], app: app)
        XCTAssertTrue(waitForAnyText(["Trips", "Viajes"], app: app, timeout: 4))
        XCTAssertTrue(anyTextExists(["Energy", "Energía", "Efficiency", "Eficiencia"], app: app))

        tapTab(["Charging", "Cargas"], app: app)
        XCTAssertTrue(waitForAnyText(["Charging", "Cargas"], app: app, timeout: 4))
        XCTAssertTrue(anyTextExists(["Costs & places", "Costes y ubicaciones", "Totals", "Totales"], app: app))

        tapTab(["Battery", "Batería"], app: app)
        XCTAssertTrue(waitForAnyText(["Battery", "Batería"], app: app, timeout: 4))
        XCTAssertTrue(anyTextExists(["Degradation", "Degradación", "Efficiency & totals", "Eficiencia y totales"], app: app))

        tapTab(["More", "Más"], app: app)
        XCTAssertTrue(waitForAnyText(["More", "Más"], app: app, timeout: 4))
        XCTAssertTrue(anyTextExists(["Statistics", "Estadísticas"], app: app))
        // Parking moved from the tab bar into More → Areas.
        if !anyTextExists(["Parking"], app: app) {
            print("HIERARCHY-DUMP-BEGIN\n\(app.debugDescription)\nHIERARCHY-DUMP-END")
        }
        XCTAssertTrue(anyTextExists(["Parking"], app: app))
    }

    private func tapTab(_ labels: [String], app: XCUIApplication) {
        for label in labels {
            let tab = app.tabBars.buttons[label]
            if tab.waitForExistence(timeout: 2) {
                tab.tap()
                return
            }

            let button = app.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return
            }
        }

        XCTFail("Could not find tab with labels: \(labels.joined(separator: ", "))")
    }

    private func waitForAnyText(_ labels: [String], app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label IN %@", labels)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    private func anyTextExists(_ labels: [String], app: XCUIApplication) -> Bool {
        let predicate = NSPredicate(format: "label IN %@", labels)
        return app.staticTexts.matching(predicate).firstMatch.exists
    }
}
