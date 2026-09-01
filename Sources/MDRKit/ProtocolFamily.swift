import Foundation

/// The two command tables Sony headsets speak. Which one a device uses is determined by the SDP
/// service it exposes, not by its model name: v2 is tried first and v1 is the fallback.
public enum MDRProtocolFamily: String, CaseIterable, Sendable {
    case v2
    case v1

    public var serviceUUID: UUID {
        switch self {
        case .v2: UUID(uuidString: "956C7B26-D49A-4BA8-B03F-B17D393CB6E2")!
        case .v1: UUID(uuidString: "96CC203E-5068-46AD-B32D-E316F5E069BA")!
        }
    }
}
