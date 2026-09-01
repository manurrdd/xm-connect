import XCTest
@testable import MDRKit

final class FramingTests: XCTestCase {
    func testPacksBatteryQuery() {
        let packed = MDRFraming.pack(MDRFrame(type: .data, sequence: 0, payload: [0x10, 0x00]))

        XCTAssertEqual(packed, [0x3E, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x02, 0x10, 0x00, 0x1E, 0x3C])
    }

    func testRoundTripsEveryDataType() {
        for type in [MDRDataType.ack, .data, .dataNo2] {
            let frame = MDRFrame(type: type, sequence: 1, payload: [0x66, 0x02])

            XCTAssertEqual(MDRFraming.unpack(MDRFraming.pack(frame)), frame)
        }
    }

    func testEscapesMarkersInPayload() {
        let frame = MDRFrame(type: .data, sequence: 0, payload: [0x3C, 0x3D, 0x3E])
        let packed = MDRFraming.pack(frame)

        XCTAssertEqual(packed.filter { $0 == 0x3E }, [0x3E], "start marker must appear once")
        XCTAssertEqual(packed.filter { $0 == 0x3C }, [0x3C], "end marker must appear once")
        XCTAssertEqual(MDRFraming.unpack(packed), frame)
    }

    func testRejectsWrongChecksum() {
        var packed = MDRFraming.pack(MDRFrame(type: .data, sequence: 0, payload: [0x10, 0x00]))
        packed[packed.count - 2] &+= 1

        XCTAssertNil(MDRFraming.unpack(packed))
    }

    func testRejectsLengthThatDisagreesWithPayload() {
        var packed = MDRFraming.pack(MDRFrame(type: .data, sequence: 0, payload: [0x10, 0x00]))
        packed[6] = 0x03
        packed[packed.count - 2] = MDRFraming.checksum(packed[1..<(packed.count - 2)])

        XCTAssertNil(MDRFraming.unpack(packed))
    }

    func testRejectsTruncatedEscapeSequence() {
        XCTAssertNil(MDRFraming.unpack([0x3E, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3D, 0x3C]))
    }

    func testRejectsFrameWithoutMarkers() {
        XCTAssertNil(MDRFraming.unpack([0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C]))
    }
}
