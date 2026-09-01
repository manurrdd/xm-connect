import XCTest
@testable import MDRKit

final class FrameReassemblerTests: XCTestCase {
    private let battery = MDRFrame(type: .data, sequence: 0, payload: [0x10, 0x00])
    private let noise = MDRFrame(type: .data, sequence: 1, payload: [0x66, 0x02])

    func testYieldsFrameSplitAcrossReads() {
        var reassembler = MDRFrameReassembler()
        let packed = MDRFraming.pack(battery)

        XCTAssertEqual(reassembler.consume(Array(packed[0..<4])), [])
        XCTAssertEqual(reassembler.consume(Array(packed[4...])), [battery])
    }

    func testYieldsBothFramesFromOneRead() {
        var reassembler = MDRFrameReassembler()

        let frames = reassembler.consume(MDRFraming.pack(battery) + MDRFraming.pack(noise))

        XCTAssertEqual(frames, [battery, noise])
    }

    func testDropsBytesBeforeStartMarker() {
        var reassembler = MDRFrameReassembler()

        XCTAssertEqual(reassembler.consume([0xFF, 0x00] + MDRFraming.pack(battery)), [battery])
    }

    func testSkipsCorruptFrameAndKeepsReading() {
        var reassembler = MDRFrameReassembler()
        var corrupt = MDRFraming.pack(battery)
        corrupt[corrupt.count - 2] &+= 1

        XCTAssertEqual(reassembler.consume(corrupt + MDRFraming.pack(noise)), [noise])
    }
}
