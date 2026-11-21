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
        let originField = app.buttons["originField"]
        XCTAssertTrue(originField.waitForExistence(timeout: 5), "Origin field should be tappable")
        XCTAssertTrue(app.buttons["destinationField"].exists)
        addScreenshot(named: "01-home-light")

        originField.tap()
        XCTAssertTrue(
            app.textFields["placeSearchField"].waitForExistence(timeout: 5),
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

        let eta = app.staticTexts["etaSummary"]
        XCTAssertTrue(eta.waitForExistence(timeout: 10), "Demo route ETA should render")
        XCTAssertTrue(app.staticTexts["演示数据"].exists, "Demo data must be clearly labelled")
        addScreenshot(named: "03-route-result-compact")

        let expand = app.buttons["expandSheet"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        expand.tap()

        XCTAssertTrue(
            app.staticTexts["可选路线"].waitForExistence(timeout: 5),
            "Expanded sheet should show route alternatives"
        )
        XCTAssertTrue(app.staticTexts["路线信息"].exists)
        addScreenshot(named: "04-route-result-expanded")

        let refresh = app.buttons["refreshRoute"]
        XCTAssertTrue(refresh.exists)
    }

    func testSettingsOpensAndShowsProviderConfiguration() throws {
        app.launch()

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["providerPicker"].exists)
        XCTAssertTrue(app.textFields["proxyURLField"].exists)
        addScreenshot(named: "05-settings")

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
        XCTAssertTrue(app.buttons["originField"].exists)
        addScreenshot(named: "06-home-dark")
    }

    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
