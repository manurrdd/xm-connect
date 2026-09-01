import Foundation

extension UInt8 {
    public var hex: String { String(format: "%02X", self) }
}

extension Sequence where Element == UInt8 {
    public var hex: String { map(\.hex).joined(separator: " ") }
}
