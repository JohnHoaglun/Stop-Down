//
//  Stop_DownUITests.swift
//  Stop-DownUITests
//
//  Created by John Hoaglun on 9/22/26.
//

import XCTest

final class Stop_DownUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Regression: the control stack was taller than the safe area, so the
    /// ZStack centered it and the top bar (lens/mode) ended up under the
    /// status bar while the Hold/Save bar was clipped off the bottom edge.
    /// The bars are now pinned with safe-area insets and the stack fits;
    /// every primary control must be fully on-screen and hittable.
    @MainActor
    func testPrimaryControlsFitOnScreen() throws {
        let app = XCUIApplication()
        app.terminate() // isolate from any state left by other tests
        app.launch()

        // On the simulator the first camera access presents a system
        // permission dialog (a Springboard overlay) a moment after launch;
        // poll briefly and dismiss it so the meter screen is reachable.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.Springboard")
        for _ in 0..<10 { // up to ~5 s
            let permissionDialog = springboard.alerts.firstMatch
            if permissionDialog.exists {
                permissionDialog.buttons["Allow"].tap()
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Switch to the DEBUG test feed so the dial and the equivalent list
        // are fully populated regardless of the simulator's virtual camera.
        // On the current simulator runtime the feed picker's segments are
        // exposed as buttons, so tap the "Test data" segment by label.
        let testFeedSegment = app.buttons["Test data"]
        XCTAssertTrue(testFeedSegment.waitForExistence(timeout: 10), "DEBUG feed picker should offer a 'Test data' segment")
        testFeedSegment.tap()

        let evReadout = app.staticTexts["ev-readout"]
        XCTAssertTrue(evReadout.waitForExistence(timeout: 10), "EV readout should appear on the test feed")
        let screen = app.frame

        // Bottom bar: fully on-screen and tappable.
        let hold = app.buttons["hold-live"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssert(hold.isHittable, "Hold button must be hittable (not clipped): \(hold.frame)")
        XCTAssert(hold.frame.maxY <= screen.maxY, "Hold button extends below the screen: \(hold.frame)")
        XCTAssert(hold.frame.minY >= screen.minY, "Hold button extends above the screen: \(hold.frame)")

        let save = app.buttons["save"]
        XCTAssert(save.isHittable, "Save button must be hittable: \(save.frame)")
        XCTAssert(save.frame.maxY <= screen.maxY, "Save button extends below the screen: \(save.frame)")

        // Top bar: reachable, not hidden under the status bar.
        let mode = app.segmentedControls["mode-control"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssert(mode.isHittable, "Mode picker must be hittable (not under the status bar): \(mode.frame)")
        XCTAssert(mode.frame.minY >= screen.minY, "Mode picker extends above the screen: \(mode.frame)")

        // Middle content: the equivalent list sits between the bars, on-screen.
        // On the current simulator runtime the list is exposed as an
        // XCUIElementType.other element, so query it by that type.
        let list = app.otherElements["equivalent-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Equivalent-exposure list should appear on the test feed")
        XCTAssert(list.frame.maxY <= screen.maxY, "Equivalent list extends below the screen: \(list.frame)")
        XCTAssert(list.frame.minY >= screen.minY, "Equivalent list extends above the screen: \(list.frame)")
    }

    /// Release readiness: the bottom-bar info button opens the About sheet,
    /// which shows the app name, the live bundle version (marketing version
    /// plus build number, so it can never drift from the Xcode build
    /// settings), the privacy statement, and the support link; the sheet
    /// closes again.
    @MainActor
    func testAboutSheetShowsVersionAndSupportLink() throws {
        let app = XCUIApplication()
        app.terminate() // isolate from any state left by other tests
        app.launch()

        // On the simulator the first camera access presents a system
        // permission dialog (a Springboard overlay) a moment after launch;
        // poll briefly and dismiss it so the meter screen is reachable.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.Springboard")
        for _ in 0..<10 { // up to ~5 s
            let permissionDialog = springboard.alerts.firstMatch
            if permissionDialog.exists {
                permissionDialog.buttons["Allow"].tap()
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        let aboutButton = app.buttons["about-button"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 10), "About button missing in the bottom bar")
        aboutButton.tap()

        let version = app.staticTexts["about-version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5), "About sheet should show a version line")
        XCTAssertTrue(
            version.label.hasPrefix("Version "),
            "Version line should read like 'Version 1.0 (11)': \(version.label)"
        )

        // The support link is exposed as an XCUIElementType.link element,
        // so query it by that type.
        let support = app.links["support-link"]
        XCTAssertTrue(support.waitForExistence(timeout: 10), "About sheet should show the support link")
        XCTAssertTrue(
            support.label.contains("hoaglun.com/stop-down"),
            "Unexpected support link label: \(support.label)"
        )

        let close = app.buttons["about-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "About sheet should have a close button")
        close.tap()
        XCTAssertFalse(version.exists, "About sheet should close")
    }
}
