import XCTest

/// The launcher's two new apps and their Shorts settings, driven from the screen.
///
/// The checks use a custom shortcut instead of waiting on Snapchat's and Facebook's
/// live pages: the browser refuses a blocked short route before the request leaves
/// the device, so this is the same native block a link in the app would hit, and it
/// stays deterministic while the sites change around it.
final class AppsProtectionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSnapchatAndFacebookShortBlocking() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-preferences"]
        app.launch()

        app.tabBars.buttons["Apps"].tap()
        XCTAssertTrue(app.buttons["Open Snapchat"].waitForExistence(timeout: 60), "Snapchat should be on the launcher")
        XCTAssertTrue(app.buttons["Open Facebook"].exists, "Facebook should be on the launcher")
        capture("Apps launcher", app: app)

        app.buttons["apps.protection-settings"].tap()
        XCTAssertTrue(app.navigationBars["Protection settings"].waitForExistence(timeout: 15))

        // Both new rows sit below the fold; scroll once so each switch is fully
        // hittable before reading or tapping it.
        app.swipeUp()
        let spotlight = app.switches["browser.hide-spotlight"]
        let facebook = app.switches["browser.hide-facebook-reels"]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10), "Snapchat Spotlight should have a switch")
        XCTAssertTrue(facebook.waitForExistence(timeout: 10), "Facebook Reels should have a switch")
        XCTAssertEqual(spotlight.value as? String, "0", "blocking starts off")
        XCTAssertEqual(facebook.value as? String, "0", "blocking starts off")
        capture("Shorts blocking settings", app: app)

        // Tap the control side of each row. The row's label is a multi-line
        // description, so a centre tap can land on the text rather than the switch.
        spotlight.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        facebook.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(waitFor { (app.switches["browser.hide-spotlight"].value as? String) == "1" },
                      "Spotlight should turn on")
        XCTAssertTrue(waitFor { (app.switches["browser.hide-facebook-reels"].value as? String) == "1" },
                      "Facebook Reels should turn on")
        app.buttons["Done"].tap()

        addShortcut(app, name: "Facebook Reels", address: "https://www.facebook.com/reels/")
        app.buttons["Facebook Reels"].tap()
        XCTAssertTrue(app.staticTexts["A little less noise"].waitForExistence(timeout: 15),
                      "a Facebook Reels link should be stopped before it loads")
        capture("Facebook Reels blocked", app: app)
        app.buttons["Back to Apps"].tap()

        addShortcut(app, name: "Snapchat Spotlight", address: "https://www.snapchat.com/spotlight")
        app.buttons["Snapchat Spotlight"].tap()
        XCTAssertTrue(app.staticTexts["A little less noise"].waitForExistence(timeout: 15),
                      "a Spotlight link should be stopped before it loads")
        capture("Snapchat Spotlight blocked", app: app)
        app.buttons["Back to Apps"].tap()

        // The two new launcher entries open their real sites in the protected
        // browser. The native header is enough to prove the session is up; the
        // sites' own content depends on the network and sign-in state.
        openLauncherApp(app, name: "Open Facebook", capture: "Facebook app", wait: 3, expectedTitle: "Facebook")
        openLauncherApp(app, name: "Open Snapchat", capture: "Snapchat app", wait: 5, expectedTitle: "Snapchat")
    }


    /// Opt-in: uses the existing WebKit login and YouTube's real controls.
    func testYouTubeLandscapeSettingsAndFloatingNavigation() throws {
        guard ProcessInfo.processInfo.environment["CLEARVIEW_LIVE_YOUTUBE_UI"] == "1" else {
            throw XCTSkip("Enable CLEARVIEW_LIVE_YOUTUBE_UI to verify the live YouTube player")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.tabBars.buttons["Apps"].tap()
        XCTAssertTrue(app.buttons["Open YouTube"].waitForExistence(timeout: 30))
        app.buttons["Open YouTube"].tap()
        let home = app.buttons["apps.youtube-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        let nav = app.otherElements["apps.youtube-floating-navigation"]
        if nav.exists {
            XCTAssertGreaterThan(nav.frame.minX, 0, "the glass capsule should float away from screen edges")
            XCTAssertLessThan(nav.frame.maxX, app.frame.width)
        }
        app.buttons["Search YouTube"].tap()
        let field = app.textFields["apps.search.query"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Julian Treasure how to speak")
        app.buttons.matching(identifier: "Search").firstMatch.tap()
        let video = app.webViews.links.matching(NSPredicate(format: "label CONTAINS %@", "How to Speak So That People Want to Listen")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 30))
        video.tap()
        let showControls = app.buttons["Show player controls"]
        XCTAssertTrue(showControls.waitForExistence(timeout: 30))
        showControls.tap()
        let enter = app.buttons["Enter full screen"]
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
        enter.tap()
        XCTAssertTrue(waitFor(timeout: 15) { app.frame.width > app.frame.height }, "fullscreen should be landscape")
        let fullscreenTitle = app.webViews.staticTexts["How to Speak So That People Want to Listen | Julian Treasure | TED"]
        XCTAssertTrue(fullscreenTitle.waitForNonExistence(timeout: 8), "the title must hide when playback controls auto-hide")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pause = app.buttons["Pause video"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(fullscreenTitle.exists, "revealing the controls during playback must not bring the title back")
        pause.tap()
        XCTAssertTrue(fullscreenTitle.waitForExistence(timeout: 5), "pausing should show the title with the controls")
        let settings = app.buttons["Playback Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        capture("YouTube landscape playback settings", app: app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "YouTube settings hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(app.frame.width > app.frame.height, "opening playback settings must stay in landscape")
        let quality = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Quality' OR label CONTAINS[c] 'Playback speed'")).firstMatch
        XCTAssertTrue(quality.waitForExistence(timeout: 10), "YouTube's settings must be visible over the fullscreen player")
        XCTAssertTrue(quality.isHittable)
        XCTAssertLessThanOrEqual(quality.frame.maxY, app.frame.height)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        if !app.buttons["Exit full screen"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let exit = app.buttons["Exit full screen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        exit.tap()
        XCTAssertTrue(waitFor(timeout: 10) { app.frame.height > app.frame.width }, "exiting should restore portrait")
        XCTAssertTrue(app.buttons["apps.youtube-home"].waitForExistence(timeout: 10))
        app.buttons["apps.youtube-home"].tap()
        XCTAssertTrue(app.buttons["apps.navigation.home"].waitForExistence(timeout: 10))
        capture("YouTube glass navigation and logo", app: app)
    }

    // MARK: - Helpers

    private func openLauncherApp(_ app: XCUIApplication, name: String, capture title: String,
                                 wait seconds: TimeInterval, expectedTitle: String) {
        app.buttons[name].tap()
        XCTAssertTrue(app.buttons["apps.filters"].waitForExistence(timeout: 30), "\(name) should open the protected browser")

        // It should look like an app: the branded title, no website address, and
        // no duplicate bottom bar over the branded site's own navigation.
        let appTitle = app.staticTexts["browser.title"]
        XCTAssertTrue(appTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(appTitle.label, expectedTitle)
        XCTAssertFalse(app.staticTexts["browser.host"].exists, "the website address must not be shown")
        XCTAssertFalse(app.buttons["apps.navigation.home"].exists,
                       "the redundant bottom bar should not cover the page")
        XCTAssertFalse(app.buttons["apps.navigation.shortVideos"].exists,
                       "the blocked short-video tab should be gone")

        Thread.sleep(forTimeInterval: seconds)
        capture(title, app: app)
        app.buttons["App menu"].tap()
        // The header's close button and this menu item share the label, so use the
        // menu item's own identifier rather than an ambiguous label query.
        let back = app.buttons["square.grid.2x2"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
    }

    private func addShortcut(_ app: XCUIApplication, name: String, address: String) {
        let add = app.buttons["Add shortcut"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), "the launcher should offer Add shortcut")
        add.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)

        let addressField = app.textFields["Website address"]
        XCTAssertTrue(addressField.exists)
        addressField.tap()
        addressField.typeText(address)

        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10), "the shortcut should be saved")
    }

    private func waitFor(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(100_000)
        }
        return condition()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
