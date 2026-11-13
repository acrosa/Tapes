import XCTest

/// End-to-end tests: they drive the real app through its controls, on a seeded demo tape
/// (two recorded tracks, eight seconds long, cues at 0:02, 0:04 and 0:06, loop on 0:04–0:06).
@MainActor
final class SpuleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        launch(reset: true)
    }

    // MARK: Helpers

    private func launch(reset: Bool) {
        app.launchArguments = (reset ? ["-resetTapes"] : []) + ["-seedDemoTape"]
        app.launch()
        XCTAssertTrue(button("Play").waitForExistence(timeout: 10))
        wait("the tape to load") { !self.display.contains("LOADING") }
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(_ label: String) -> XCUIElement { app.buttons[label] }

    /// Everything the display window shows, as one string.
    private var display: String {
        let window = app.descendants(matching: .any).matching(identifier: "display").firstMatch
        return window.label + " " + ((window.value as? String) ?? "")
    }

    /// Tape position in seconds, read from the counter in the display.
    private var position: Double {
        let text = display.split(separator: " ").last.map(String.init) ?? ""
        let parts = text.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
            XCTFail("Unreadable position: \(text)")
            return -1
        }
        return minutes * 60 + seconds
    }

    private func value(of label: String) -> String { (element(label).value as? String) ?? "" }

    private func wait(_ what: String, timeout: TimeInterval = 5, until condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Timed out waiting for \(what). Display: \(display)")
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Drags from the centre of `target` by an offset in points.
    private func drag(_ target: XCUIElement, dx: CGFloat = 0, dy: CGFloat = 0) {
        let from = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    // MARK: Transport

    func testPlayAdvancesTheTapeAndStopHaltsIt() {
        XCTAssertTrue(display.contains("STOP"))
        if value(of: "loop") == "on" { button("loop").tap() }
        button("Play").tap()
        wait("PLAY in the display") { self.display.contains("PLAY") }
        pause(1.5)
        let moving = position
        XCTAssertGreaterThan(moving, 1.0)
        button("Stop").tap()
        wait("STOP in the display") { self.display.contains("STOP") }
        pause(0.6)
        let rest = position
        pause(0.6)
        XCTAssertEqual(position, rest, accuracy: 0.02, "The tape should not move once stopped")

        button("Return to start").tap()
        wait("the tape at the start") { self.position < 0.01 }
    }

    func testPlaybackStopsItselfAtTheEndOfTheRecording() {
        if value(of: "loop") == "on" { button("loop").tap() }
        let scale = element("Tape scale")
        // The scale shows one minute; the recording is eight seconds long.
        scale.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5)).tap()
        XCTAssertGreaterThan(position, 5)
        button("Play").tap()
        wait("the tape to stop at the end", timeout: 8) { self.button("Play").exists && self.display.contains("STOP") }
        XCTAssertEqual(position, 8, accuracy: 0.3)
    }

    // MARK: Recording

    func testRecordingPutsAudioOnTheSelectedTrackAndItSurvivesARelaunch() {
        // Track 3 is empty on the demo tape: its menu offers no erase.
        element("Track 3").tap()
        wait("track 3 selected") { self.button("Record on track 3").exists }
        element("Track 3").press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Mute"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Erase track 3"].exists)
        app.buttons["Mute"].tap()
        wait("track 3 muted") { self.value(of: "Track 3").contains("muted") }

        button("Record on track 3").tap()
        allowMicrophoneIfAsked()
        wait("REC 3 in the display", timeout: 8) { self.display.contains("REC 3") }
        pause(2.0)
        XCTAssertGreaterThan(position, 1.0, "The tape should run while recording")
        button("Stop recording").tap()
        wait("the recording to be saved") { self.display.contains("SAVED TO TRACK 3") }

        element("Track 3").press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Erase track 3"].waitForExistence(timeout: 3), "Track 3 should now hold audio")
        app.buttons["Unmute"].tap()

        pause(1.5)      // let the track and the tape's settings reach the disk
        app.terminate()
        launch(reset: false)
        element("Track 3").press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Erase track 3"].waitForExistence(timeout: 3), "The recording should survive a relaunch")
        app.buttons["Erase track 3"].tap()
        wait("the erase to be confirmed") { self.display.contains("TRACK 3 ERASED") }
        element("Track 3").press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Mute"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Erase track 3"].exists, "An erased track has nothing left to erase")
    }

    private func allowMicrophoneIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK"] {
            let allow = springboard.buttons[label]
            if allow.waitForExistence(timeout: 2) {
                allow.tap()
                return
            }
        }
    }

    // MARK: Dial and scale

    func testTurningTheDialMovesTheTape() {
        button("Return to start").tap()
        let dial = element("Tape dial")
        let right = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let bottom = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        // A quarter turn clockwise is half a second of tape.
        right.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(1.0)
        XCTAssertGreaterThan(position, 0.2)
        XCTAssertLessThan(position, 1.5)
        let rest = position
        pause(0.5)
        XCTAssertEqual(position, rest, accuracy: 0.02, "A stopped tape should come to rest after a turn")

        dial.doubleTap()
        wait("the tape back at the start") { self.position < 0.01 }
    }

    func testTouchingTheScaleMovesTheTapeThere() {
        let scale = element("Tape scale")
        scale.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // The scale shows one minute, so its middle is thirty seconds.
        XCTAssertEqual(position, 30, accuracy: 3)
    }

    // MARK: Cues and loop

    func testCuesCanBeSteppedThroughAddedAndRemoved() {
        let window = app.descendants(matching: .any).matching(identifier: "display").firstMatch
        button("Return to start").tap()
        window.swipeLeft()
        wait("cue 1") { abs(self.position - 2) < 0.01 }
        window.swipeLeft()
        wait("cue 2") { abs(self.position - 4) < 0.01 }
        window.swipeRight()
        wait("cue 1 again") { abs(self.position - 2) < 0.01 }

        button("cue").tap()         // resting on cue 1: this removes it
        wait("the cue to be cleared") { self.display.contains("CUE CLEARED") }
        button("Return to start").tap()
        window.swipeLeft()
        wait("the old cue 2, now the first") { abs(self.position - 4) < 0.01 }

        button("Return to start").tap()
        button("cue").tap()         // at the start there is no cue yet: this adds one
        wait("a new cue") { self.display.contains("CUE 1") }
    }

    func testLoopRepeatsTheSectionThePlayheadIsIn() {
        XCTAssertEqual(value(of: "loop"), "on", "The demo tape starts with its loop on")
        button("loop").tap()
        wait("the loop off") { self.value(of: "loop") == "off" }

        // At the start, the section runs from 0:00 to the first cue at 0:02.
        button("Return to start").tap()
        button("loop").tap()
        wait("the loop on") { self.value(of: "loop") == "on" }
        XCTAssertTrue(display.contains("LOOP 0:00–0:02"), display)

        button("Play").tap()
        for _ in 0..<8 {
            pause(0.5)
            XCTAssertLessThan(position, 2.1, "The tape should stay inside the loop")
        }
        button("loop").tap()
        wait("the tape to run on past the loop", timeout: 6) { self.position > 2.5 }
        button("Stop").tap()
    }

    // MARK: Wheels and keys

    func testSpeedWheelRollsHoldsAtDoubleSpeedAndResets() {
        let speed = element("speed")
        XCTAssertEqual(speed.value as? String, "1.00 times")
        drag(speed, dy: -40)
        XCTAssertNotEqual(speed.value as? String, "1.00 times")
        // From 1× the wheel leaves its detent after 8pt, then 60pt is one octave: 2×, held for 16pt.
        pause(1.0)      // a double-tap straight after letting go of a roll is not picked up
        speed.doubleTap()
        wait("speed back at 1×") { (speed.value as? String) == "1.00 times" }
        drag(speed, dy: -76)
        XCTAssertEqual(speed.value as? String, "2.00 times")
        pause(1.0)      // a double-tap straight after letting go of a roll is not picked up
        speed.doubleTap()
        wait("speed back at 1×") { (speed.value as? String) == "1.00 times" }
    }

    func testTempoWheelHoldsAtEveryTenBeats() {
        let tempo = element("tempo")
        XCTAssertEqual(tempo.value as? String, "120 beats per minute")
        // 6pt to leave the detent at 120, 20pt for ten beats, then a 12pt hold at 130.
        drag(tempo, dy: -32)
        XCTAssertEqual(tempo.value as? String, "130 beats per minute")
        drag(tempo, dy: 60)
        XCTAssertNotEqual(tempo.value as? String, "130 beats per minute")
    }

    func testClickKeySwitchesTheMetronome() {
        XCTAssertEqual(value(of: "click"), "off")
        button("click").tap()
        wait("the click on") { self.value(of: "click") == "on" && self.display.contains("CLICK ON") }
        button("click").tap()
        wait("the click off") { self.value(of: "click") == "off" }
    }

    func testTrackKeyDragSetsLevelAndPan() {
        let track = element("Track 2")
        XCTAssertTrue((track.value as? String ?? "").contains("level 100 percent"))
        drag(track, dy: 60)
        let lowered = track.value as? String ?? ""
        XCTAssertFalse(lowered.contains("level 100 percent"), lowered)
        drag(track, dx: 60)
        wait("a pan readout") { self.display.contains("T2 PAN R") }

        track.tap()
        wait("track 2 selected") { self.button("Record on track 2").exists }
        track.press(forDuration: 1.0)
        app.buttons["Solo"].tap()
        wait("track 2 solo") { self.value(of: "Track 2").contains("solo") }
    }

    // MARK: Tapes and export

    func testTapesCanBeCreatedRenamedAndReopened() {
        button("Tapes and settings").tap()
        XCTAssertTrue(app.staticTexts["Tape 01"].waitForExistence(timeout: 5))
        app.buttons["New tape"].tap()
        wait("the new tape in the display") { self.display.contains("Tape 02") }
        XCTAssertFalse(button("export").isEnabled, "An empty tape has nothing to export")

        button("Tapes and settings").tap()
        let row = app.staticTexts["Tape 01"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Rename"].tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(" demo")
        app.alerts.buttons["Rename"].tap()
        let renamed = app.staticTexts["Tape 01 demo"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        wait("the first tape back in the display") { self.display.contains("Tape 01 demo") }
    }

    func testAFinishCanBeChosenAndIsRemembered() {
        button("Tapes and settings").tap()
        let green = app.buttons["Green finish"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        wait("green chosen") { green.isSelected }
        XCTAssertFalse(app.buttons["Light finish"].isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(button("Play").isHittable)

        app.terminate()
        launch(reset: false)
        button("Tapes and settings").tap()
        XCTAssertTrue(app.buttons["Green finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Green finish"].isSelected, "The finish should be remembered")
        app.buttons["Light finish"].tap()
    }

    func testExportMixesDownAndOffersTheFile() {
        XCTAssertTrue(button("export").isEnabled)
        button("export").tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "The share sheet should appear with the mixdown")
    }

    // MARK: Grid

    /// With the layout grid shown, GridKit marks every checked part that is off a column edge
    /// or off the baseline. There should be none, upright or sideways.
    func testEveryPartSitsOnTheGrid() {
        app.terminate()
        app.launchArguments = ["-resetTapes", "-seedDemoTape", "-showsGrid", "YES"]
        app.launch()
        XCTAssertTrue(button("Play").waitForExistence(timeout: 10))
        let faults = app.descendants(matching: .any).matching(identifier: "grid-fault")
        pause(1.0)
        XCTAssertEqual(faults.count, 0, "Upright: " + faults.allElementsBoundByIndex.map(\.label).joined(separator: "; "))

        XCUIDevice.shared.orientation = .landscapeLeft
        pause(1.5)
        XCTAssertEqual(faults.count, 0, "Sideways: " + faults.allElementsBoundByIndex.map(\.label).joined(separator: "; "))
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Landscape

    func testLandscapeShowsEveryControlAndTheTransportWorks() {
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(1.5)
        for label in ["Play", "Return to start", "Record on track 1", "click", "cue", "loop", "Tapes and settings", "export"] {
            XCTAssertTrue(button(label).isHittable, "\(label) should be reachable in landscape")
        }
        for label in ["speed", "tempo", "Tape dial", "Tape scale", "Track 1", "Track 2", "Track 3", "Track 4"] {
            XCTAssertTrue(element(label).isHittable, "\(label) should be reachable in landscape")
        }
        if value(of: "loop") == "on" { button("loop").tap() }
        button("Play").tap()
        wait("PLAY in the display") { self.display.contains("PLAY") }
        pause(1.0)
        XCTAssertGreaterThan(position, 0.5)
        button("Stop").tap()
        drag(element("tempo"), dy: -32)
        XCTAssertEqual(value(of: "tempo"), "130 beats per minute")
        XCUIDevice.shared.orientation = .portrait
    }
}
