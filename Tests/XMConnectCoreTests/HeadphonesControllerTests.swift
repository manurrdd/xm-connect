import MDRKit
import XCTest
@testable import XMConnectCore

@MainActor
final class HeadphonesControllerTests: XCTestCase {
    private var source = FakeSource()

    private func makeController() -> HeadphonesController {
        var timings = HeadphonesController.Timings()
        timings.handshake = 0.05
        timings.release = 0.05
        timings.retry = 0.05
        timings.maximumRetry = 0.05
        return HeadphonesController(source: source, timings: timings)
    }

    override func setUp() {
        super.setUp()
        source = FakeSource()
    }

    func testOpensAChannelWhenAViewAppears() {
        let controller = makeController()

        controller.acquire()

        XCTAssertEqual(source.links.count, 1)
        XCTAssertTrue(source.links.first?.isOpen == true)
    }

    func testLeavesADisconnectedHeadsetAlone() {
        source.devices = [.offline]
        let controller = makeController()

        controller.acquire()

        XCTAssertTrue(source.links.isEmpty, "connecting it is the user's decision")
        XCTAssertTrue(controller.isOffline)
    }

    func testSaysNothingIsThereWhenNoHeadsetIsPaired() {
        source.devices = []
        let controller = makeController()

        controller.acquire()

        XCTAssertFalse(controller.isOffline)
        XCTAssertNil(controller.device)
    }

    func testGoesLiveOnceTheHandshakeSettles() {
        let controller = makeController()
        controller.acquire()

        source.links.first?.settle()

        XCTAssertTrue(controller.isLive)
        XCTAssertEqual(controller.device?.name, "WH-1000XM4")
        XCTAssertTrue(controller.hasReading)
    }

    func testHoldsTheChannelWhileAnotherViewIsStillShowing() async {
        let controller = makeController()
        controller.acquire()
        controller.acquire()
        source.links.first?.settle()

        controller.relinquish()
        await settleTimers()

        XCTAssertFalse(source.links[0].isClosed)
        XCTAssertTrue(controller.isLive)
    }

    func testLetsGoOfTheChannelWhenTheLastViewCloses() async {
        let controller = makeController()
        controller.acquire()
        source.links.first?.settle()

        controller.relinquish()
        await settleTimers()

        XCTAssertTrue(source.links[0].isClosed)
        XCTAssertFalse(controller.isLive)
    }

    func testKeepsTheLastReadingAfterLettingGo() async {
        let controller = makeController()
        controller.acquire()
        source.links.first?.settle()

        controller.relinquish()
        await settleTimers()

        XCTAssertTrue(controller.hasReading, "reopening should not start from an empty panel")
    }

    func testReconnectingKeepsShowingTheReadingUntilTheNewSessionSpeaks() async {
        let controller = makeController()
        controller.acquire()
        source.links.first?.settle()
        controller.relinquish()
        await settleTimers()

        controller.acquire()

        XCTAssertTrue(controller.hasReading)
        XCTAssertFalse(controller.isLive, "shown, but not yet confirmed")
    }

    func testGivesUpOnAChannelThatNeverFinishesTheHandshake() async {
        let controller = makeController()

        controller.acquire()
        await settleTimers()

        XCTAssertTrue(source.links[0].isClosed)
        XCTAssertGreaterThan(source.links.count, 1, "and tries again")
    }

    func testForgetsTheReadingWhenTheHeadsetDropsOff() async {
        let controller = makeController()
        controller.acquire()
        source.links.first?.settle()

        source.links.first?.close()

        XCTAssertFalse(controller.hasReading)
        XCTAssertFalse(controller.isLive)
    }

    func testRetriesAfterALinkThatWillNotOpen() async {
        source.failToLink = true
        let controller = makeController()

        controller.acquire()
        await settleTimers()

        source.failToLink = false
        await settleTimers()

        XCTAssertFalse(source.links.isEmpty, "it kept trying and got through")
        XCTAssertTrue(source.links.last?.isOpen == true)
    }

    func testStopsRetryingOnceNothingIsShowing() async {
        source.devices = [.offline]
        let controller = makeController()
        controller.acquire()

        controller.relinquish()
        await settleTimers()
        source.devices = [.connected]
        await settleTimers()

        XCTAssertTrue(source.links.isEmpty, "nothing is watching, so nothing should connect")
    }

    private func settleTimers() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
