import XCTest
@testable import MDRKit

final class PayloadTests: XCTestCase {
    /// Captured from a WH-1000XM4.
    private let xm4Functions: [UInt8] = [
        0x07, 0x00, 0x17,
        0x71, 0x38, 0x62, 0xF5, 0x81, 0x51, 0xA1, 0xE1, 0xE2, 0xD2, 0xF6, 0xD1,
        0xF4, 0xF3, 0x39, 0x12, 0x13, 0x11, 0x30, 0xC1, 0x14, 0x22, 0x21,
    ]

    func testReadsProtocolVersionFromV1() {
        let info = MDRProtocolInfo(payload: [0x01, 0x00, 0x70, 0x00], family: .v1)

        XCTAssertEqual(info?.version, 0x7000)
        XCTAssertNil(info?.tables, "v1 does not report table support")
    }

    func testReadsProtocolVersionAndTablesFromV2() {
        let info = MDRProtocolInfo(payload: [0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01], family: .v2)

        XCTAssertEqual(info?.version, 2)
        XCTAssertEqual(info?.tables, MDRTableSupport(table1: true, table2: false))
    }

    func testReadsOneByteFunctionListFromV1() {
        let functions = MDRSupportFunctions(payload: xm4Functions, family: .v1)

        XCTAssertEqual(functions?.ids.count, 23)
        XCTAssertEqual(functions?.ids.first, 0x71)
        XCTAssertEqual(functions?.ids.last, 0x21)
    }

    func testReadsPairedFunctionListFromV2() {
        let payload: [UInt8] = [0x07, 0x00, 0x03, 0x6B, 0x00, 0x20, 0x01, 0x23, 0x00]

        XCTAssertEqual(MDRSupportFunctions(payload: payload, family: .v2)?.ids, [0x6B, 0x20, 0x23])
    }

    func testRejectsV1ListReadWithV2Layout() {
        XCTAssertNil(MDRSupportFunctions(payload: xm4Functions, family: .v2))
    }

    func testXM4AnnouncesNoiseControlEqualizerBatteryAndPowerOff() {
        let ids = MDRSupportFunctions(payload: xm4Functions, family: .v1)?.ids ?? []

        XCTAssertTrue(ids.contains(0x62), "noise cancelling and ambient sound")
        XCTAssertTrue(ids.contains(0x51), "preset equalizer")
        XCTAssertTrue(ids.contains(0x11), "battery level")
        XCTAssertTrue(ids.contains(0x21), "power off")
        XCTAssertFalse(ids.contains(0x15), "an over-ear model has no left/right battery")
    }
}
