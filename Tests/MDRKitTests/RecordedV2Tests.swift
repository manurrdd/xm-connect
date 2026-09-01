import XCTest
@testable import MDRKit

/// Frames from a recorded WF-1000XM5 session on firmware 6.1.0. Nobody here owns one, so this is
/// what keeps the v2 path honest.
final class RecordedV2Tests: XCTestCase {
    func testReadsProtocolInfo() {
        let info = MDRProtocolInfo(payload: [0x01, 0x00, 0x03, 0x00, 0x30, 0x18, 0x00, 0x00], family: .v2)

        XCTAssertEqual(info?.version, 0x03003018)
        XCTAssertEqual(info?.tables, MDRTableSupport(table1: true, table2: true))
    }

    func testReadsThePairedFunctionList() {
        let payload: [UInt8] = [
            0x07, 0x00, 0x0B,
            0x10, 0xFF, 0x12, 0xFF, 0x13, 0xFF, 0x23, 0xFF, 0x29, 0xFF,
            0x2A, 0xFF, 0x50, 0x11, 0x6B, 0x08, 0x70, 0x01, 0xA1, 0x12, 0xC1, 0xFF,
        ]

        let functions = MDRSupportFunctions(payload: payload, family: .v2)?.ids

        XCTAssertEqual(functions?.count, 11)
        XCTAssertEqual(functions?.contains(0x6B), true, "noise cancelling with ambient level")
        XCTAssertEqual(V2Command.noiseVariant(forFunction: 0x6B), 0x17)
    }

    func testReadsNoiseState() {
        let noise = V2NoiseControl(payload: [0x67, 0x17, 0x01, 0x00, 0x01, 0x00, 0x14])

        XCTAssertEqual(noise?.mode, .off)
    }

    func testReadsSixBandEqualizerOnACustomPreset() {
        let equalizer = MDREqualizer(
            payload: [0x57, 0x00, 0xA0, 0x06, 0x14, 0x0B, 0x0A, 0x0D, 0x09, 0x0C], family: .v2
        )

        XCTAssertEqual(equalizer?.preset, 0xA0)
        XCTAssertEqual(equalizer?.clearBass, 10)
        XCTAssertEqual(equalizer?.bands, [1, 0, 3, -1, 2])
    }

    func testReadsEarbudBatteriesReportedWithThresholds() {
        XCTAssertEqual(
            MDRBattery(payload: [0x23, 0x09, 0x00, 0x00, 0x64, 0x00, 0x64, 0x64], family: .v2),
            .leftRight(
                left: MDRBatteryLevel(percent: 0, charging: .notCharging),
                right: MDRBatteryLevel(percent: 100, charging: .notCharging)
            )
        )
    }

    func testReadsCaseBattery() {
        XCTAssertEqual(
            MDRBattery(payload: [0x23, 0x0A, 0x35, 0x00, 0x1E], family: .v2),
            .cradle(MDRBatteryLevel(percent: 53, charging: .notCharging))
        )
    }

    func testReadsAGeneralSettingSlot() {
        let subject = Array("SIDETONE_SETTING".utf8)
        let summary = Array("SIDETONE_SETTING_SUMMARY".utf8)
        let payload: [UInt8] = [0xD1, 0xD1, 0x00, 0x01, UInt8(subject.count)]
            + subject + [UInt8(summary.count)] + summary

        let info = MDRGeneralSettingInfo(payload: payload, family: .v2)

        XCTAssertEqual(info?.subject, "SIDETONE_SETTING")
        XCTAssertEqual(info?.displayName, "Sidetone")
    }

    func testReadsGeneralSettingValuesOnTheirOwnPolarity() {
        XCTAssertEqual(MDRGeneralSettingValue(payload: [0xD7, 0xD1, 0x00, 0x01], family: .v2)?.isOn, false)
        XCTAssertEqual(MDRGeneralSettingValue(payload: [0xD7, 0xD2, 0x00, 0x00], family: .v2)?.isOn, true)
    }

    func testDoesNotReadAV2SlotAsAV1One() {
        XCTAssertNil(MDRGeneralSettingValue(payload: [0xD7, 0xD1, 0x00, 0x01], family: .v1))
    }
}
