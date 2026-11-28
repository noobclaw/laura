import XCTest

/// UI tests. Names carry the TEST-CASES.md ids; screenshots go to $SIMULATOR_HOST_HOME/ui-shots/<lang>/.
final class UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Helpers

    @discardableResult
    func launch(_ lang: String = "en", pro: Bool = false, reset: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITour", "-AppleLanguages", "(\(lang))", "-AppleLocale", lang == "en" ? "en_US" : lang] + extra
        if reset { app.launchArguments.append("-UITourReset") }
        if pro { app.launchArguments.append("-UITourPro") }
        app.launch()
        return app
    }

    func shot(_ app: XCUIApplication, _ name: String, _ lang: String = "en") {
        let host = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: host).appendingPathComponent("ui-shots/\(lang)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = XCUIScreen.main.screenshot()
        try? s.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        let a = XCTAttachment(screenshot: s)
        a.name = "\(lang)-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    func waitForShelf(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home-sources"].waitForExistence(timeout: 20), "shelf appears without any setup")
        var tries = 0
        while !app.buttons["album-Harbor Lights"].waitForExistence(timeout: tries == 0 ? 25 : 3) && tries < 6 {
            app.swipeUp(); tries += 1
        }
        XCTAssertTrue(app.buttons["album-Harbor Lights"].exists, "demo shelf appears without any setup")
        for _ in 0..<tries { app.swipeDown() }
    }

    func openAlbum(_ app: XCUIApplication, _ title: String = "Harbor Lights") {
        let b = app.buttons["album-\(title)"]
        if !b.isHittable { app.swipeUp() }
        b.tap()
        XCTAssertTrue(app.buttons["album-play"].waitForExistence(timeout: 8))
    }

    func startPlaying(_ app: XCUIApplication) {
        openAlbum(app)
        app.buttons["track-0"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 8))
    }

    func tab(_ app: XCUIApplication, _ i: Int) { app.tabBars.buttons.element(boundBy: i).tap() }

    // MARK: Shelf

    func test_TC_HOME_01_TC_HOME_02_TC_HOME_03_TC_LIB_13_firstLaunchPlaysWithoutSetup() {
        let app = launch()
        waitForShelf(app)
        XCTAssertTrue(app.buttons["home-share"].exists)
        XCTAssertTrue(app.buttons["home-settings"].exists)
        XCTAssertTrue(app.buttons["home-sources"].exists)
        openAlbum(app)
        XCTAssertTrue(app.staticTexts["Harbor Lights"].exists)
        XCTAssertTrue(app.buttons["album-download"].exists)
        app.buttons["track-0"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["mini-player"].label.contains("Low Tide"))
    }

    func test_TC_HOME_05_emptyStateOffersBothSources() {
        let app = launch()
        waitForShelf(app)
        app.buttons["home-sources"].tap()
        app.cells.element(boundBy: 0).tap()
        app.buttons["source-remove"].tap()
        app.buttons["Remove source and its downloads"].tap()
        if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 3) { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.buttons["empty-add-webdav"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Choose a folder"].exists)
    }

    func test_TC_SHR_01_shareShelfCard() {
        let app = launch()
        waitForShelf(app)
        app.buttons["home-share"].tap()
        XCTAssertTrue(app.images["share-preview"].waitForExistence(timeout: 8))
        shot(app, "share-shelf")
    }

    // MARK: Library

    func test_TC_LIB_06_searchGroupsResults() {
        let app = launch()
        waitForShelf(app)
        tab(app, 1)
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("tide")
        XCTAssertTrue(app.buttons["search-track-0"].waitForExistence(timeout: 5))
    }

    func test_TC_LIB_14_artistPage() {
        let app = launch()
        waitForShelf(app)
        openAlbum(app)
        app.buttons["Spindle Demo Ensemble"].tap()
        XCTAssertTrue(app.buttons["Shuffle all"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["album-Copper Sky"].exists || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Copper Sky'")).count > 0)
    }

    // MARK: Limits and Pro

    func test_TC_SRC_08_TC_IAP_01_secondSourceOpensPaywall() {
        let app = launch(extra: ["-UITourFakeSource"])
        waitForShelf(app)
        app.buttons["home-sources"].tap()
        app.buttons["add-source"].tap()
        XCTAssertTrue(app.staticTexts["paywall-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["paywall-title"].label, "Add as many servers as you like")
        XCTAssertTrue(app.buttons["paywall-buy"].exists)
        XCTAssertTrue(app.buttons["paywall-restore"].exists)
        shot(app, "paywall-sources")
    }

    func test_TC_PLY_10_sleepTimerIsPro() {
        let app = launch()
        waitForShelf(app)
        startPlaying(app)
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.buttons["now-sleep"].waitForExistence(timeout: 5))
        app.buttons["now-sleep"].tap()
        XCTAssertTrue(app.staticTexts["paywall-title"].waitForExistence(timeout: 5))
    }

    func test_TC_PL_01_TC_PL_02_playlistsAndLimit() {
        let app = launch()
        waitForShelf(app)
        tab(app, 2)
        for name in ["Road", "Night"] {
            app.buttons["playlists-new"].tap()
            let f = app.alerts.textFields.firstMatch
            XCTAssertTrue(f.waitForExistence(timeout: 5))
            f.typeText(name)
            app.alerts.buttons["Create"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        }
        app.buttons["playlists-new"].tap()
        XCTAssertTrue(app.staticTexts["paywall-title"].waitForExistence(timeout: 5), "third playlist needs Pro")
    }

    func test_TC_PL_01_addSongToPlaylist() {
        let app = launch(pro: true)
        waitForShelf(app)
        openAlbum(app)
        app.buttons["track-1"].press(forDuration: 1.2)
        app.buttons["Add to Playlist"].tap()
        let f = app.textFields["New playlist name"]
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap(); f.typeText("Walk")
        app.buttons["playlist-create"].tap()
        tab(app, 2)
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 songs"].exists || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 '")).count > 0)
    }

    // MARK: Playback and offline

    func test_TC_PLY_12_TC_SHR_03_nowPlayingAndShare() {
        let app = launch(pro: true)
        waitForShelf(app)
        startPlaying(app)
        app.buttons["mini-player"].tap()
        XCTAssertTrue(app.staticTexts["now-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["now-turntable"].exists)
        sleep(2)
        shot(app, "now-playing")
        app.buttons["now-share"].tap()
        XCTAssertTrue(app.images["share-preview"].waitForExistence(timeout: 8))
    }

    func test_TC_OFF_01_downloadAlbum() {
        let app = launch(pro: true)
        waitForShelf(app)
        openAlbum(app)
        app.buttons["album-download"].tap()
        XCTAssertTrue(app.images["Downloaded"].waitForExistence(timeout: 20))
    }

    // MARK: Settings and language

    func test_TC_SET_01_TC_SET_03_TC_RVW_06_settingsRows() {
        let app = launch()
        waitForShelf(app)
        app.buttons["home-settings"].tap()
        let lang = app.buttons["settings-language"]
        XCTAssertTrue(lang.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-pro"].exists)
        XCTAssertLessThan(app.buttons["settings-pro"].frame.minY, lang.frame.minY)
        XCTAssertLessThan(lang.frame.minY, app.buttons["settings-sources"].frame.minY, "language is the first row after Pro")
        XCTAssertTrue(app.buttons["settings-rate"].exists)
        shot(app, "settings")
    }

    func test_TC_SET_02_languageSwitchesInstantlyAndPersists() {
        let app = launch()
        waitForShelf(app)
        app.buttons["home-settings"].tap()
        app.buttons["settings-language"].tap()
        app.buttons["lang-ja"].tap()
        XCTAssertTrue(app.tabBars.buttons["検索"].waitForExistence(timeout: 8))
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.tabBars.buttons["検索"].waitForExistence(timeout: 15), "choice survives a relaunch")
    }

    // MARK: Robustness

    func test_TC_CRASH_01_rapidTaps() {
        let app = launch()
        waitForShelf(app)
        for _ in 0..<3 { for i in [1, 2, 0] { tab(app, i) } }
        for _ in 0..<4 {
            openAlbum(app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        startPlaying(app)
        for _ in 0..<10 { app.buttons["mini-toggle"].tap() }
        XCTAssertEqual(app.state, .runningForeground)
    }

    func test_TC_UX_01_largestText() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        waitForShelf(app)
        shot(app, "ax-shelf")
        XCTAssertTrue(app.buttons["home-settings"].isHittable)
        openAlbum(app)
        shot(app, "ax-album")
        XCTAssertTrue(app.buttons["album-play"].exists)
    }

    func test_TC_UX_02_lightAndDark() {
        for scheme in ["-UITourLight", "-UITourDark"] {
            let app = launch(extra: [scheme])
            waitForShelf(app)
            shot(app, "scheme\(scheme)-shelf")
            startPlaying(app)
            app.buttons["mini-player"].tap()
            XCTAssertTrue(app.staticTexts["now-title"].waitForExistence(timeout: 5))
            sleep(1)
            shot(app, "scheme\(scheme)-now")
            app.terminate()
        }
    }

    // MARK: Tours (screenshots in four languages; the English one is also the App Review video)

    func testTourEnglish() { tour("en") }
    func test_TC_L10N_02_tourTraditionalChinese() { tour("zh-Hant") }
    func test_TC_L10N_02_tourJapanese() { tour("ja") }
    func test_TC_L10N_02_tourGerman() { tour("de") }

    private func tour(_ lang: String) {
        let app = launch(lang)
        waitForShelf(app)
        sleep(1)
        shot(app, "01-shelf", lang)
        app.swipeUp()
        shot(app, "02-shelf-albums", lang)
        app.swipeDown()
        openAlbum(app)
        shot(app, "03-album", lang)
        app.buttons["track-0"].tap()
        XCTAssertTrue(app.buttons["mini-player"].waitForExistence(timeout: 8))
        app.buttons["mini-player"].tap()
        sleep(2)
        shot(app, "04-now-playing", lang)
        app.buttons["now-queue"].tap()
        sleep(1)
        shot(app, "05-queue", lang)
        app.buttons["queue-done"].tap()
        XCTAssertTrue(app.buttons["now-close"].waitForExistence(timeout: 5))
        app.buttons["now-close"].tap()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home-sources"].waitForExistence(timeout: 5))
        tab(app, 1)
        let f = app.textFields["search-field"]
        if f.waitForExistence(timeout: 5) { f.tap(); f.typeText("light") }
        sleep(1)
        shot(app, "06-search", lang)
        tab(app, 2)
        shot(app, "07-playlists", lang)
        tab(app, 0)
        app.buttons["home-sources"].tap()
        sleep(1)
        shot(app, "08-sources", lang)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["home-settings"].tap()
        sleep(1)
        shot(app, "09-settings", lang)
        app.buttons["settings-pro"].tap()
        sleep(1)
        shot(app, "10-paywall", lang)
        app.buttons["paywall-close"].tap()
        sleep(1)
        app.buttons["settings-sources"].tap()
        app.buttons["add-source"].tap()
        sleep(1)
        shot(app, "11-add-source", lang)
    }
}
