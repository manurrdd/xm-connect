import XCTest
import MDRKit
@testable import MDRSession

/// Frames captured from a WH-1000XM4.
private enum XM4 {
    static let protocolInfo: [UInt8] = [0x01, 0x00, 0x70, 0x00]
    static let supportFunctions: [UInt8] = [
        0x07, 0x00, 0x17,
        0x71, 0x38, 0x62, 0xF5, 0x81, 0x51, 0xA1, 0xE1, 0xE2, 0xD2, 0xF6, 0xD1,
        0xF4, 0xF3, 0x39, 0x12, 0x13, 0x11, 0x30, 0xC1, 0x14, 0x22, 0x21,
    ]
    static let noiseCapability: [UInt8] = [0x61, 0x02, 0x02, 0x00, 0x01, 0x02, 0x00, 0x14, 0x01, 0x14]
    static let noiseOff: [UInt8] = [0x67, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x14]
    static let equalizerCapability: [UInt8] = [
        0x51, 0x01, 0x06, 0x15, 0x02,
        0x00, 0x03, 0x4F, 0x66, 0x66,
        0xA0, 0x06, 0x43, 0x75, 0x73, 0x74, 0x6F, 0x6D,
    ]
    static let equalizer: [UInt8] = [0x57, 0x01, 0x00, 0x06, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]
    static let battery: [UInt8] = [0x11, 0x00, 0x5A, 0x00]
    static let touchPanelName: [UInt8] =
        [0xD1, 0xD1, 0x02, 0x13] + Array("TOUCH_PANEL_SETTING".utf8) + [0x00, 0x01, 0x00]
    static let touchPanelOff: [UInt8] = [0xD7, 0xD1, 0x01, 0x00]
    static let multipointName: [UInt8] =
        [0xD1, 0xD2, 0x02, 0x12] + Array("MULTIPOINT_SETTING".utf8) + [0x00, 0x01, 0x00]
    static let multipointOn: [UInt8] = [0xD7, 0xD2, 0x01, 0x01]
    static let upscalingOn: [UInt8] = [0xE7, 0x02, 0x00, 0x01]
    static let pauseWhenRemovedOn: [UInt8] = [0xF7, 0x03, 0x00, 0x01]
    static let speakToChatOff: [UInt8] = [0xF7, 0x05, 0x00, 0x00]
    static let autoPowerOffWhenRemoved: [UInt8] = [0xF7, 0x04, 0x01, 0x10, 0x00]
}

final class MDRSessionTests: XCTestCase {
    private var link = FakeLink()
    private var session: MDRSession!

    override func setUp() {
        super.setUp()
        link = FakeLink()
        session = MDRSession(family: .v1, link: link)
    }

    func testAsksForTheProtocolInfoFirst() throws {
        try session.start()

        XCTAssertEqual(link.commands, [[0x00, 0x00]])
    }

    func testWaitsForAcknowledgementBeforeTheNextCommand() throws {
        try session.start()
        XCTAssertEqual(link.commands.count, 1)

        link.reply(XM4.protocolInfo)

        XCTAssertEqual(link.commands.last, [0x06, 0x00])
    }

    func testAcknowledgesWhatTheDeviceSends() throws {
        try session.start()

        link.reply(XM4.protocolInfo)

        XCTAssertEqual(link.acknowledgements, 1)
    }

    func testQueriesOnlyWhatTheDeviceAnnounces() throws {
        try settle()

        XCTAssertEqual(Array(link.commands.dropFirst(2)), [
            [0x60, 0x02],  // noise capability
            [0x66, 0x02],  // noise state
            [0x10, 0x00],  // battery, single level only
            [0x50, 0x01, 0x01],  // equalizer capability
            [0x56, 0x01],  // equalizer
            [0xD0, 0xD1, 0x01], [0xD6, 0xD1],
            [0xD0, 0xD2, 0x01], [0xD6, 0xD2],
            [0xE6, 0x02],
            [0xF6, 0x03], [0xF6, 0x05],
            [0xF6, 0x04],
        ])
    }

    func testReadsCapabilitiesFromTheAnnouncedFunctions() throws {
        try connect()

        let capabilities = session.state.capabilities
        XCTAssertTrue(capabilities.hasNoiseCancelling)
        XCTAssertTrue(capabilities.hasAmbientSound)
        XCTAssertTrue(capabilities.hasEqualizer)
        XCTAssertTrue(capabilities.hasPowerOff)
        XCTAssertEqual(capabilities.batteries, [.single])
    }

    func testTakesAmbientRangeAndModesFromTheCapabilityReply() throws {
        try settle()

        XCTAssertEqual(session.state.capabilities.ambientSteps, 20)
        XCTAssertTrue(session.state.capabilities.supportsFocusOnVoice)
        XCTAssertTrue(session.state.capabilities.supportsWindReduction)
    }

    func testKeepsTheStateTheDeviceReports() throws {
        try settle()

        XCTAssertEqual(session.state.noise, .off)
        XCTAssertEqual(session.state.equalizer?.bands, [0, 0, 0, 0, 0])
        XCTAssertEqual(session.state.battery, .single(MDRBatteryLevel(percent: 90, charging: .notCharging)))
        XCTAssertTrue(session.state.isReady)
    }

    func testIgnoresTheSecondTableFunctionList() throws {
        try connect()
        let announced = session.state.capabilities

        // A WF-1000XM5 sends its table 2 list on the other data type, in a different id namespace.
        link.acknowledge()
        link.onFrame?(MDRFrame(type: .dataNo2, sequence: 0, payload: [
            0x07, 0x00, 0x0B, 0x42, 0x3D, 0x2D, 0x53, 0xFF, 0x54, 0xFF, 0xF1, 0xFF, 0x60, 0xFF,
        ]))

        XCTAssertEqual(session.state.capabilities, announced, "table 2 must not redefine the device")
    }

    func testKeepsEarbudAndCaseBatteriesApart() throws {
        try connect()

        // Earbuds report both, one after the other.
        link.reply([0x11, 0x01, 0x50, 0x00, 0x64, 0x00])
        link.reply([0x11, 0x02, 0x35, 0x00])

        XCTAssertEqual(earbuds?.left.percent, 80)
        XCTAssertEqual(earbuds?.right.percent, 100)
        XCTAssertEqual(session.state.caseBattery?.percent, 53)
    }

    private var earbuds: (left: MDRBatteryLevel, right: MDRBatteryLevel)? {
        guard case .leftRight(let left, let right) = session.state.battery else { return nil }
        return (left, right)
    }

    func testNamesTheSettingsTheDeviceExposes() throws {
        try settle()

        XCTAssertEqual(session.state.settings.map(\.name), ["Touch panel", "Multipoint"])
        XCTAssertEqual(session.state.settings.map(\.isOn), [false, true])
        XCTAssertEqual(session.state.upscaling, true)
    }

    func testReadsTheSystemSettingsTheDeviceAnnounces() throws {
        try settle()

        XCTAssertEqual(session.state.systemSwitches[.pauseWhenRemoved], true)
        XCTAssertEqual(session.state.systemSwitches[.speakToChat], false)
        XCTAssertEqual(session.state.autoPowerOff?.active, .whenRemoved)
        XCTAssertEqual(session.state.autoPowerOff?.selectedDelay, .afterFiveMinutes)
    }

    func testWritesASystemSwitch() throws {
        try settle()

        session.setSystemSwitch(.speakToChat, isOn: true)

        XCTAssertEqual(link.commands.last, [0xF8, 0x05, 0x00, 0x01])
        XCTAssertEqual(session.state.systemSwitches[.speakToChat], true)
    }

    func testWritesAPowerOffDelayAsBothActiveAndRemembered() throws {
        try settle()

        session.setAutoPowerOff(.afterThreeHours)

        XCTAssertEqual(link.commands.last, [0xF8, 0x04, 0x01, 0x03, 0x03])
    }

    func testKeepsTheRememberedDelayWhenChoosingAMode() throws {
        try settle()

        session.setAutoPowerOff(.never)

        XCTAssertEqual(link.commands.last, [0xF8, 0x04, 0x01, 0x11, 0x00])
    }

    func testWritesASettingAndShowsItStraightAway() throws {
        try settle()

        session.setSetting(slot: 0xD1, isOn: true)

        XCTAssertEqual(link.commands.last, [0xD8, 0xD1, 0x01, 0x01])
        XCTAssertEqual(session.state.settings.first?.isOn, true)
    }

    func testReadsASettingBackAfterWritingIt() throws {
        try settle()

        session.setSetting(slot: 0xD1, isOn: true)
        link.reply(XM4.touchPanelOff)

        XCTAssertEqual(session.state.settings.first?.isOn, false, "the device has the last word")
    }

    func testWritesNoiseWithTheSettingTypesTheDeviceReported() throws {
        try settle()

        session.setNoise(.ambient(level: 12, focusOnVoice: true))

        XCTAssertEqual(link.commands.last, [0x68, 0x02, 0x11, 0x02, 0x00, 0x01, 0x01, 0x0C])
        XCTAssertEqual(session.state.noise, .ambient(level: 12, focusOnVoice: true))
    }

    func testDoesNotWriteNoiseBeforeTheDeviceSaysHow() throws {
        try connect()

        session.setNoise(.noiseCancelling(windReduction: false))

        XCTAssertFalse(link.commands.contains { $0.first == 0x68 })
        XCTAssertNil(session.state.noise)
    }

    func testCorrectsAnOptimisticStateWhenTheDeviceDisagrees() throws {
        try settle()

        session.setNoise(.noiseCancelling(windReduction: false))
        link.reply(XM4.noiseOff)

        XCTAssertEqual(session.state.noise, .off)
    }

    func testForgetsEverythingWhenTheLinkDrops() throws {
        try settle()
        var closed = false
        session.onClose = { closed = true }

        link.close()

        XCTAssertNil(session.state.noise)
        XCTAssertFalse(session.state.isReady)
        XCTAssertTrue(closed)
    }

    private func connect() throws {
        try session.start()
        link.reply(XM4.protocolInfo)
        link.reply(XM4.supportFunctions)
    }

    /// Connects and answers every query the device's capability list triggers.
    private func settle() throws {
        try connect()
        link.reply(XM4.noiseCapability)
        link.reply(XM4.noiseOff)
        link.reply(XM4.battery)
        link.reply(XM4.equalizerCapability)
        link.reply(XM4.equalizer)
        link.reply(XM4.touchPanelName)
        link.reply(XM4.touchPanelOff)
        link.reply(XM4.multipointName)
        link.reply(XM4.multipointOn)
        link.reply(XM4.upscalingOn)
        link.reply(XM4.pauseWhenRemovedOn)
        link.reply(XM4.speakToChatOff)
        link.reply(XM4.autoPowerOffWhenRemoved)
    }
}
