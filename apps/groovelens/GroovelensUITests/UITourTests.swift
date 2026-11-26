import XCTest

/// Walks every screen in several languages and saves screenshots for review (G6 / G6b).
/// Screens are found by accessibility identifiers, so the same flow runs in every language.
final class UITourTests: XCTestCase {
    private let languages = ["en", "zh-Hant", "ja", "de"]
    private var outDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        outDir = URL(fileURLWithPath: home).appendingPathComponent("ui-shots")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    private func shot(_ lang: String, _ name: String) {
        let dir = outDir.appendingPathComponent(lang)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func tapIfExists(_ e: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        guard e.waitForExistence(timeout: timeout) else { return false }
        e.tap()
        return true
    }

    func testTourAllScreens() throws {
        for (index, lang) in languages.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-UITour", "-groovelens.language", lang, "-AppleLanguages", "(\(lang))"]
            app.launch()
            sleep(3)
            shot(lang, "01-home")

            // First language: the seeded demo song is analyzing in a sheet.
            if index == 0, app.buttons["close-analysis"].waitForExistence(timeout: 10) {
                sleep(2)
                shot(lang, "02-analysis-running")
                _ = app.buttons["open-chart"].waitForExistence(timeout: 240)
                sleep(1)
                shot(lang, "03-analysis-done")
                app.buttons["open-chart"].tap()
            } else {
                let row = app.descendants(matching: .any)["song-row"].firstMatch
                let deadline = Date().addingTimeInterval(240)
                while (row.value as? String) != "ready" && Date() < deadline { sleep(2) }
                shot(lang, "02-home-with-song")
                row.tap()
            }

            XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 15), "song detail did not open")
            sleep(1)
            shot(lang, "04-song-detail")

            // Kit mode is Pro → paywall.
            if tapIfExists(app.buttons["mode-kit"]) {
                sleep(2)
                shot(lang, "05-paywall")
                _ = tapIfExists(app.buttons["close-pro"])
                sleep(1)
            }

            if tapIfExists(app.buttons["chart-button"]) {
                sleep(2)
                shot(lang, "06-chart")
                _ = tapIfExists(app.buttons["chart-back"])
                sleep(1)
            }

            // Play the song in Tap mode, tapping the pads along the way.
            app.buttons["start"].tap()
            sleep(5)
            shot(lang, "07-stage-countin")
            let window = app.windows.firstMatch
            for i in 0..<24 {
                let x = [0.1, 0.27, 0.43, 0.6, 0.77, 0.93][i % 6]
                window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.93)).tap()
                usleep(250_000)
            }
            shot(lang, "08-stage-playing")
            if index == 0 {
                _ = tapIfExists(app.buttons["pause"])
                sleep(1)
                shot(lang, "09-paused")
                // Resume: the first neon button in the pause overlay.
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            }
            XCTAssertTrue(app.buttons["results-done"].waitForExistence(timeout: 90), "results did not appear")
            sleep(3)
            shot(lang, "10-results")
            app.buttons["results-done"].tap()
            sleep(1)
            _ = tapIfExists(app.buttons["back"])

            for (tab, name) in [("tab-fills", "11-fills"), ("tab-progress", "12-progress"), ("tab-settings", "13-settings")] {
                if tapIfExists(app.buttons[tab]) { sleep(2); shot(lang, name) }
            }
            if tapIfExists(app.buttons["language-row"]) {
                sleep(2)
                shot(lang, "14-language-picker")
            }
            app.terminate()
        }
    }
}
