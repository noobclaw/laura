import XCTest

/// Visits every screen in four languages and saves screenshots to $SIMULATOR_HOST_HOME/ui-shots
/// (CI copies them out). Fails if an expected control is missing.
final class UITourTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String, _ lang: String) {
        let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: host).appendingPathComponent("ui-shots/\(lang)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "\(lang)-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func launch(_ lang: String, pro: Bool, noir: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITour", "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "en" ? "en_US" : lang]
        if pro { app.launchArguments.append("-UITourPro") }
        if noir { app.launchArguments.append("-UITourNoir") }
        app.launch()
        return app
    }

    func testTourEnglish() { tour("en") }
    func testTourTraditionalChinese() { tour("zh-Hant") }
    func testTourJapanese() { tour("ja") }
    func testTourGerman() { tour("de") }

    private func tour(_ lang: String) {
        let app = launch(lang, pro: true)
        XCTAssertTrue(app.buttons["add-material"].waitForExistence(timeout: 10))
        shot(app, "01-bench", lang)

        app.buttons["section-analysis"].tap()
        sleep(1)
        shot(app, "02-analysis", lang)
        app.swipeUp()
        shot(app, "03-analysis-more", lang)
        app.swipeDown(); app.swipeDown()

        app.buttons["section-product"].tap()
        sleep(1)
        shot(app, "04-product", lang)
        app.buttons["section-formula"].tap()
        sleep(1)

        // Add a line through the picker (retry once: the first tap can land during the section animation).
        app.buttons["add-material"].tap()
        if !app.navigationBars.firstMatch.waitForExistence(timeout: 5) { app.buttons["add-material"].tap() }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "05-picker", lang)
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pick-'")).element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let field = app.textFields["amount-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("2.5")
        shot(app, "06-line-editor", lang)
        app.buttons["save-line"].tap()

        // Weighing sheet and weigh mode.
        app.buttons["weigh"].tap()
        XCTAssertTrue(app.buttons["start-weighing"].waitForExistence(timeout: 5))
        shot(app, "07-plan", lang)
        app.buttons["start-weighing"].tap()
        XCTAssertTrue(app.buttons["weigh-next"].waitForExistence(timeout: 5))
        shot(app, "08-weigh", lang)
        for _ in 0..<30 {
            if app.buttons["save-batch"].exists { break }
            if app.buttons["weigh-next"].exists { app.buttons["weigh-next"].tap() }
        }
        XCTAssertTrue(app.buttons["save-batch"].waitForExistence(timeout: 5))
        app.buttons["save-batch"].tap()
        sleep(1)
        shot(app, "09-weigh-done", lang)
        // "Done" closes the weigh cover and the plan sheet together.
        app.buttons["weigh-close"].tap()
        XCTAssertTrue(app.buttons["add-material"].waitForExistence(timeout: 5))

        app.buttons["tab-shelf"].tap()
        XCTAssertTrue(app.buttons["new-formula"].waitForExistence(timeout: 5))
        shot(app, "10-shelf", lang)

        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["language-row"].waitForExistence(timeout: 5))
        shot(app, "11-settings", lang)
        app.buttons["language-row"].tap()
        sleep(1)
        shot(app, "12-language", lang)
        app.swipeDown(velocity: .fast)
        sleep(1)
        app.swipeDown(velocity: .fast)
        sleep(1)

        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["new-material"].waitForExistence(timeout: 5))
        shot(app, "13-library", lang)
        let mat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'material-'")).element(boundBy: 0)
        if mat.waitForExistence(timeout: 3) {
            mat.tap()
            sleep(1)
            shot(app, "14-material", lang)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.buttons["tab-lab"].tap()
        sleep(1)
        shot(app, "15-batches", lang)

        app.buttons["tab-library"].tap()
        if app.buttons["open-dilution"].waitForExistence(timeout: 5) {
            app.buttons["open-dilution"].tap()
            sleep(1)
            shot(app, "16-dilution", lang)
            app.swipeDown(velocity: .fast)
            sleep(1)
        }
    }

    /// Noir look: bench, weighing, shelf, share card.
    func testTourNoir() {
        let lang = "noir"
        let app = launch("en", pro: true, noir: true)
        XCTAssertTrue(app.buttons["add-material"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "01-bench", lang)
        app.buttons["spray"].tap()
        usleep(500_000)
        shot(app, "02-spray", lang)
        app.buttons["weigh"].tap()
        XCTAssertTrue(app.buttons["start-weighing"].waitForExistence(timeout: 5))
        app.buttons["start-weighing"].tap()
        XCTAssertTrue(app.buttons["weigh-next"].waitForExistence(timeout: 5))
        app.buttons["weigh-next"].tap(); app.buttons["weigh-next"].tap(); app.buttons["weigh-next"].tap()
        sleep(1)
        shot(app, "03-weigh", lang)
        app.buttons["Stop weighing"].firstMatch.exists ? app.buttons["Stop weighing"].firstMatch.tap() : app.buttons.element(boundBy: 0).tap()
        sleep(1)
        app.swipeDown(velocity: .fast)
        sleep(1)
        app.buttons["formula-menu"].tap()
        let card = app.buttons["Share card"]
        if card.waitForExistence(timeout: 3) {
            card.tap()
            sleep(2)
            shot(app, "04-share-card", lang)
            app.swipeDown(velocity: .fast)
            sleep(1)
        }
        app.buttons["tab-shelf"].tap()
        sleep(2)
        shot(app, "05-shelf", lang)
        app.buttons["open-settings"].tap()
        sleep(1)
        shot(app, "06-settings", lang)
    }

    /// Free user: the formula limit opens the paywall with a store price (from the .storekit file in Debug).
    func testFreePaywall() {
        let app = launch("en", pro: false)
        XCTAssertTrue(app.buttons["tab-shelf"].waitForExistence(timeout: 10))
        app.buttons["tab-shelf"].tap()
        for i in 0..<6 {
            app.buttons["new-formula"].tap()
            if app.buttons["create-formula"].waitForExistence(timeout: 3) {
                app.textFields["new-formula-name"].typeText("Trial \(i)")
                app.buttons["create-formula"].tap()
                app.buttons["tab-shelf"].tap()
            } else {
                break
            }
        }
        XCTAssertTrue(app.staticTexts["Your 5 free formulas are full"].waitForExistence(timeout: 5))
        shot(app, "20-paywall", "en")
    }
}
