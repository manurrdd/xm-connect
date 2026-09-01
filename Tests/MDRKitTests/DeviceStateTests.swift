import XCTest
@testable import MDRKit

/// Replies captured from a WH-1000XM4, except where a v2 case is noted.
final class DeviceStateTests: XCTestCase {
    func testReadsNoiseCapability() {
        let capability = V1NoiseCapability(payload: [0x61, 0x02, 0x02, 0x00, 0x01, 0x02, 0x00, 0x14, 0x01, 0x14])

        XCTAssertEqual(capability?.ncSettingType, 0x02)
        XCTAssertEqual(capability?.ncStep, 0)
        XCTAssertEqual(capability?.asmSettingType, 0x01)
        XCTAssertEqual(capability?.ambientModes, [
            .init(id: 0x00, steps: 20),
            .init(id: 0x01, steps: 20),
        ])
    }

    func testReadsNoiseStateWithSettingTypesTheDeviceReports() {
        let noise = V1NoiseControl(payload: [0x67, 0x02, 0x00, 0x02, 0x00, 0x01, 0x00, 0x14])

        XCTAssertEqual(noise?.effect, 0x00)
        XCTAssertEqual(noise?.ncSettingType, 0x02, "the device reports dual/single/off, not level adjustment")
        XCTAssertEqual(noise?.asmSettingType, 0x01)
        XCTAssertEqual(noise?.asmId, 0x00)
        XCTAssertEqual(noise?.asmLevel, 20)
    }

    func testIgnoresNoiseReplyOfAnotherInquiry() {
        XCTAssertNil(V1NoiseControl(payload: [0x67, 0x03, 0x11, 0x01, 0x00, 0x01, 0x00, 0x05]))
    }

    func testReadsEqualizerCapability() {
        let payload: [UInt8] = [
            0x51, 0x01, 0x06, 0x15, 0x02,
            0x00, 0x03, 0x4F, 0x66, 0x66,
            0xA0, 0x06, 0x43, 0x75, 0x73, 0x74, 0x6F, 0x6D,
        ]

        let capability = MDREqualizerCapability(payload: payload, family: .v1)

        XCTAssertEqual(capability?.bandCount, 6)
        XCTAssertEqual(capability?.stepCount, 21)
        XCTAssertEqual(capability?.presets, [
            .init(id: 0x00, name: "Off"),
            .init(id: 0xA0, name: "Custom"),
        ])
    }

    func testRejectsEqualizerCapabilityThatRunsPastItsEnd() {
        XCTAssertNil(MDREqualizerCapability(payload: [0x51, 0x01, 0x06, 0x15, 0x01, 0x00, 0x09, 0x4F], family: .v1))
    }

    func testNamesPresetsTheDeviceLeftBlank() {
        // A WH-1000XM4 announces twelve presets, every one of them with an empty name.
        let payload: [UInt8] = [
            0x51, 0x01, 0x06, 0x15, 0x0C,
            0x00, 0x00, 0x10, 0x00, 0x11, 0x00, 0x12, 0x00, 0x13, 0x00, 0x14, 0x00,
            0x15, 0x00, 0x16, 0x00, 0x17, 0x00, 0xA0, 0x00, 0xA1, 0x00, 0xA2, 0x00,
        ]

        let capability = MDREqualizerCapability(payload: payload, family: .v1)

        XCTAssertEqual(capability?.presets.count, 12)
        XCTAssertEqual(capability?.presets.map(\.displayName).prefix(3), ["Off", "Bright", "Excited"])
        XCTAssertEqual(capability?.presets.last?.displayName, "Custom 2")
    }

    func testKeepsTheNameTheDeviceGives() {
        let payload: [UInt8] = [0x51, 0x01, 0x06, 0x15, 0x01, 0x10, 0x05, 0x43, 0x6C, 0x61, 0x72, 0x6F]

        XCTAssertEqual(MDREqualizerCapability(payload: payload, family: .v1)?.presets.first?.displayName, "Claro")
    }

    func testReadsFlatSixBandEqualizer() {
        let equalizer = MDREqualizer(
            payload: [0x57, 0x01, 0x00, 0x06, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A], family: .v1
        )

        XCTAssertEqual(equalizer?.preset, 0x00)
        XCTAssertEqual(equalizer?.clearBass, 0)
        XCTAssertEqual(equalizer?.bands, [0, 0, 0, 0, 0])
    }

    func testReadsTenBandEqualizerOnItsOwnScale() {
        let payload: [UInt8] = [0x57, 0x00, 0xA1, 0x0A, 0x00, 0x0C, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06, 0x06]

        let equalizer = MDREqualizer(payload: payload, family: .v2)

        XCTAssertNil(equalizer?.clearBass, "ten-band devices have no clear bass")
        XCTAssertEqual(equalizer?.bands, [-6, 6, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testReadsPresetWithoutBands() {
        let equalizer = MDREqualizer(payload: [0x57, 0x01, 0x14, 0x00], family: .v1)

        XCTAssertEqual(equalizer?.preset, 0x14)
        XCTAssertEqual(equalizer?.bands, [])
    }

    func testRejectsEqualizerOfTheOtherFamily() {
        let payload: [UInt8] = [0x57, 0x01, 0x00, 0x06, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A]

        XCTAssertNil(MDREqualizer(payload: payload, family: .v2))
    }

    func testReadsSingleBattery() {
        XCTAssertEqual(
            MDRBattery(payload: [0x11, 0x00, 0x5A, 0x00], family: .v1),
            .single(MDRBatteryLevel(percent: 90, charging: .notCharging))
        )
    }

    func testReadsLeftRightBattery() {
        XCTAssertEqual(
            MDRBattery(payload: [0x23, 0x01, 0x50, 0x01, 0x46, 0x00], family: .v2),
            .leftRight(
                left: MDRBatteryLevel(percent: 80, charging: .charging),
                right: MDRBatteryLevel(percent: 70, charging: .notCharging)
            )
        )
    }

    func testReadsBatteryFromNotification() {
        XCTAssertEqual(
            MDRBattery(payload: [0x13, 0x00, 0x64, 0x03], family: .v1),
            .single(MDRBatteryLevel(percent: 100, charging: .charged))
        )
    }

    func testRejectsBatteryReplyOfTheOtherFamily() {
        XCTAssertNil(MDRBattery(payload: [0x11, 0x00, 0x5A, 0x00], family: .v2))
    }
}
