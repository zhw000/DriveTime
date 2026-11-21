import XCTest

final class DriveTimeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testHomeScreenAndPlaceSearchEntry() throws {
        app.launch()

        XCTAssertTrue(
            app.staticTexts["DriveTime"].waitForExistence(timeout: 8),
            "DriveTime header should appear"
        )
        let originField = element("originField")
        XCTAssertTrue(originField.waitForExistence(timeout: 5), "Origin field should be tappable")
        XCTAssertTrue(element("destinationField").exists)
        addScreenshot(named: "01-home-light")

        originField.tap()
        XCTAssertTrue(
            element("placeSearchField").waitForExistence(timeout: 5),
            "Tapping the origin field should open place search"
        )
        addScreenshot(named: "02-place-search")

        let cancel = app.buttons["取消"].firstMatch
        if cancel.exists {
            cancel.tap()
        }
    }

    func testDemoRouteResultAndSheetExpansion() throws {
        app.launchArguments += ["-DriveTimeDemo"]
        app.launch()

        let eta = element("etaSummary")
        XCTAssertTrue(eta.waitForExistence(timeout: 10), "Demo route ETA should render")
        XCTAssertTrue(app.staticTexts["演示数据"].exists, "Demo data must be clearly labelled")
        addScreenshot(named: "03-route-result-compact")

        let expand = element("expandSheet")
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        expand.tap()

        XCTAssertTrue(
            app.staticTexts["可选路线"].waitForExistence(timeout: 5),
            "Expanded sheet should show route alternatives"
        )
        XCTAssertTrue(app.staticTexts["路线信息"].exists)
        addScreenshot(named: "04-route-result-expanded")

        XCTAssertTrue(element("refreshRoute").exists)

        let alternative = element("routeOption-备选路线 2")
        XCTAssertTrue(alternative.waitForExistence(timeout: 3), "Second route option should exist")
        let etaBefore = eta.label
        alternative.tap()
        let etaChanged = NSPredicate(format: "label != %@", etaBefore)
        expectation(for: etaChanged, evaluatedWith: eta, handler: nil)
        waitForExpectations(timeout: 5)
        addScreenshot(named: "05-route-alternative-selected")
    }

    func testSettingsOpensAndShowsProviderConfiguration() throws {
        app.launch()

        let settings = element("settingsButton")
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("providerPicker").exists)
        XCTAssertTrue(element("proxyURLField").exists)
        addScreenshot(named: "06-settings")

        let done = app.buttons["完成"].firstMatch
        if done.exists {
            done.tap()
        }
    }

    func testDarkModeHomeRenders() throws {
        app.launchArguments += ["-DriveTimeDarkMode"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["DriveTime"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(element("originField").exists)
        addScreenshot(named: "07-home-dark")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
