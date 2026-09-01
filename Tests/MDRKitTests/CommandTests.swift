import XCTest
@testable import MDRKit

final class CommandTests: XCTestCase {
    /// Setting types as a WH-1000XM4 reports them.
    private let xm4 = V1NoiseSettingTypes(
        V1NoiseCapability(payload: [0x61, 0x02, 0x02, 0x00, 0x01, 0x02, 0x00, 0x14, 0x01, 0x14])!
    )

    func testWritesNoiseOff() {
        XCTAssertEqual(
            V1Command.setNoise(.off, settingTypes: xm4),
            [0x68, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00]
        )
    }

    func testWritesNoiseCancelling() {
        XCTAssertEqual(
            V1Command.setNoise(.noiseCancelling(windReduction: false), settingTypes: xm4),
            [0x68, 0x02, 0x11, 0x02, 0x02, 0x01, 0x00, 0x00]
        )
    }

    func testWritesWindReductionAsTheSingleMicrophoneMode() {
        XCTAssertEqual(
            V1Command.setNoise(.noiseCancelling(windReduction: true), settingTypes: xm4),
            [0x68, 0x02, 0x11, 0x02, 0x01, 0x01, 0x00, 0x00]
        )
    }

    func testWritesAmbientWithFocusOnVoice() {
        XCTAssertEqual(
            V1Command.setNoise(.ambient(level: 10, focusOnVoice: true), settingTypes: xm4),
            [0x68, 0x02, 0x11, 0x02, 0x00, 0x01, 0x01, 0x0A]
        )
    }

    func testClampsAmbientLevelToTheRangeTheDeviceAccepts() {
        let low = V1Command.setNoise(.ambient(level: 0, focusOnVoice: false), settingTypes: xm4)
        let high = V1Command.setNoise(.ambient(level: 99, focusOnVoice: false), settingTypes: xm4)

        XCTAssertEqual(low.last, 1)
        XCTAssertEqual(high.last, 20)
    }

    func testCarriesTheSettingTypesTheDeviceReported() {
        let other = V1NoiseSettingTypes(
            V1NoiseControl(payload: [0x67, 0x02, 0x11, 0x01, 0x02, 0x00, 0x00, 0x00])!
        )

        let command = V1Command.setNoise(.noiseCancelling(windReduction: false), settingTypes: other)

        XCTAssertEqual(command[3], 0x01)
        XCTAssertEqual(command[5], 0x00)
    }

    func testWritesNoiseOnEachV2Variant() {
        let ambient = MDRNoiseMode.ambient(level: 5, focusOnVoice: false)

        XCTAssertEqual(V2Command.setNoise(ambient, variant: 0x17), [0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x05])
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: 0x19),
            [0x68, 0x19, 0x01, 0x01, 0x01, 0x00, 0x05, 0x00, 0x00]
        )
        XCTAssertEqual(V2Command.setNoise(ambient, variant: 0x22), [0x68, 0x22, 0x01, 0x01, 0x00, 0x05])
    }

    func testWritesEqualizerPreset() {
        XCTAssertEqual(V1Command.setEqualizerPreset(0xA1), [0x58, 0x01, 0xA1, 0x00])
        XCTAssertEqual(V2Command.setEqualizerPreset(0xA1), [0x58, 0x00, 0xA1, 0x00])
    }

    func testWritesSixBandsOffsetByTen() {
        let command = V1Command.setEqualizerBands(preset: 0xA0, clearBass: 3, bands: [0, -10, 10, 0, 0])

        XCTAssertEqual(command, [0x58, 0x01, 0xA0, 0x06, 13, 10, 0, 20, 10, 10])
    }

    func testWritesTenBandsOffsetBySix() {
        let command = V2Command.setEqualizerBands(preset: 0xA0, clearBass: nil, bands: Array(repeating: -6, count: 10))

        XCTAssertEqual(command, [0x58, 0x00, 0xA0, 0x0A] + Array(repeating: UInt8(0), count: 10))
    }

    func testRoundTripsBandsThroughTheParser() {
        let command = V1Command.setEqualizerBands(preset: 0xA0, clearBass: -4, bands: [1, 2, 3, 4, 5])

        var reply = command
        reply[0] = 0x57
        let parsed = MDREqualizer(payload: reply, family: .v1)

        XCTAssertEqual(parsed?.clearBass, -4)
        XCTAssertEqual(parsed?.bands, [1, 2, 3, 4, 5])
    }

    func testWritesPowerOff() {
        XCTAssertEqual(V1Command.powerOff(), [0x22, 0x00, 0x01])
        XCTAssertEqual(V2Command.powerOff(), [0x24, 0x03, 0x01])
    }
}
