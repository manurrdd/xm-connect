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

    private func variant(_ function: UInt8) -> V2NoiseVariant {
        V2NoiseVariant.forFunction(function)!
    }

    func testWritesAmbientOnEachV2Variant() {
        let ambient = MDRNoiseMode.ambient(level: 5, focusOnVoice: false)

        // Dual noise cancelling with a seamless ambient level, as the WH-1000XM5 announces it.
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: variant(0x6B)),
            [0x68, 0x17, 0x01, 0x01, 0x01, 0x00, 0x05]
        )
        // The same, with noise adaptation reported off at standard sensitivity.
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: variant(0x6D)),
            [0x68, 0x19, 0x01, 0x01, 0x01, 0x00, 0x05, 0x00, 0x00]
        )
        // Ambient only: no mode field, because there is nothing to switch to.
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: variant(0x67)),
            [0x68, 0x22, 0x01, 0x01, 0x00, 0x05]
        )
        // Dual or single cancelling plus a mode field.
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: variant(0x6A)),
            [0x68, 0x16, 0x01, 0x01, 0x01, 0x00, 0x00, 0x05]
        )
        // Cancelling on or off, no mode field.
        XCTAssertEqual(
            V2Command.setNoise(ambient, variant: variant(0x64)),
            [0x68, 0x13, 0x01, 0x01, 0x00, 0x00, 0x05]
        )
    }

    func testWritesNoiseCancellingOnEachV2Variant() {
        let cancelling = MDRNoiseMode.noiseCancelling(windReduction: false)

        XCTAssertEqual(
            V2Command.setNoise(cancelling, variant: variant(0x6B)),
            [0x68, 0x17, 0x01, 0x01, 0x00, 0x00, 0x00]
        )
        // Dual is 02 where the field carries dual, single or off.
        XCTAssertEqual(
            V2Command.setNoise(cancelling, variant: variant(0x65)),
            [0x68, 0x14, 0x01, 0x01, 0x02, 0x00, 0x00]
        )
        // On or off fields only take 01.
        XCTAssertEqual(
            V2Command.setNoise(cancelling, variant: variant(0x64)),
            [0x68, 0x13, 0x01, 0x01, 0x01, 0x00, 0x00]
        )
    }

    func testWritesWindReductionWhereTheVariantHasARoomForIt() {
        let wind = MDRNoiseMode.noiseCancelling(windReduction: true)

        XCTAssertEqual(V2Command.setNoise(wind, variant: variant(0x65))[4], 0x01, "single microphone")
        XCTAssertEqual(V2Command.setNoise(wind, variant: variant(0x6B)).count, 7, "no field to carry it")
    }

    func testRoundTripsEveryV2VariantThroughTheParser() {
        let modes: [MDRNoiseMode] = [
            .off,
            .noiseCancelling(windReduction: false),
            .ambient(level: 12, focusOnVoice: true),
        ]

        for function: UInt8 in [0x64, 0x65, 0x68, 0x6A, 0x6B, 0x6D, 0x67] {
            let variant = variant(function)
            for mode in modes {
                var reply = V2Command.setNoise(mode, variant: variant)
                reply[0] = 0x67

                let parsed = V2NoiseControl(payload: reply)?.mode

                if function == 0x67, case .noiseCancelling = mode {
                    continue  // an ambient-only device has nothing to come back as
                }
                XCTAssertEqual(parsed, mode, "function \(function.hex)")
            }
        }
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
