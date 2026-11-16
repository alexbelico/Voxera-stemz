import XCTest

final class SmokeUITests: XCTestCase {
    func testChromeOnEveryTab() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Voxera Stemz"].waitForExistence(timeout: 20))
        for name in ["Cadenas", "Herramientas", "Historial", "Cola", "Ajustes"] {
            let tab = app.tabBars.buttons[name]
            if tab.waitForExistence(timeout: 5) {
                tab.tap()
            } else {
                app.buttons[name].tap()
            }
            XCTAssertTrue(app.staticTexts["Voxera Stemz"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["CREATED BY ALEXMOET"].exists)
        }
        XCTAssertTrue(app.buttons["Probar clave"].waitForExistence(timeout: 5))
        let protect = app.switches["No gastar créditos en modelos gratis"]
        XCTAssertTrue(protect.exists || app.staticTexts["No gastar créditos en modelos gratis"].exists)
    }
}
