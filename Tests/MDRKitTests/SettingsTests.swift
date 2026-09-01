import XCTest
@testable import MDRKit

/// Replies captured from a WH-1000XM4.
final class SettingsTests: XCTestCase {
    private func capability(_ subject: String, summary: String = "") -> [UInt8] {
        let subject = Array(subject.utf8)
        let summary = Array(summary.utf8)
        return [0xD1, 0xD1, 0x02, UInt8(subject.count)] + subject
            + [UInt8(summary.count)] + summary + [0x01, 0x00]
    }

    func testNamesASlotFromTheEnumKeyTheDeviceSends() {
        let info = MDRGeneralSettingInfo(payload: capability("TOUCH_PANEL_SETTING"))

        XCTAssertEqual(info?.subject, "TOUCH_PANEL_SETTING")
        XCTAssertEqual(info?.displayName, "Touch panel")
        XCTAssertEqual(info?.isEnumKey, true)
    }

    func testKeepsTheSummaryAndNamesAnUnknownKey() {
        let info = MDRGeneralSettingInfo(
            payload: capability("MULTIPOINT_SETTING", summary: "MULTIPOINT_SETTING_SUMMARY")
        )

        XCTAssertEqual(info?.displayName, "Multipoint")
        XCTAssertEqual(info?.summary, "MULTIPOINT_SETTING_SUMMARY")
    }

    func testReadsBooleanSlots() {
        XCTAssertEqual(MDRGeneralSettingValue(payload: [0xD7, 0xD1, 0x01, 0x00])?.isOn, false)
        XCTAssertEqual(MDRGeneralSettingValue(payload: [0xD7, 0xD2, 0x01, 0x01])?.isOn, true)
    }

    func testReadsListSlotsAsAnIndex() {
        let value = MDRGeneralSettingValue(payload: [0xD7, 0xD3, 0x02, 0x03])

        XCTAssertNil(value?.isOn)
        XCTAssertEqual(value?.index, 3)
    }

    func testReadsSlotChangeNotification() {
        XCTAssertEqual(MDRGeneralSettingValue(payload: [0xD9, 0xD2, 0x01, 0x00])?.isOn, false)
    }

    func testWritesASlot() {
        XCTAssertEqual(V1Command.setGeneralSetting(slot: 0xD1, isOn: true), [0xD8, 0xD1, 0x01])
    }

    func testReadsUpscaling() {
        XCTAssertEqual(MDRUpscaling(payload: [0xE7, 0x02, 0x00, 0x01])?.isOn, true)
        XCTAssertEqual(MDRUpscaling(payload: [0xE7, 0x02, 0x00, 0x00])?.isOn, false)
    }

    func testWritesUpscaling() {
        XCTAssertEqual(V1Command.setUpscaling(isOn: true), [0xE8, 0x02, 0x00, 0x01])
    }
}
