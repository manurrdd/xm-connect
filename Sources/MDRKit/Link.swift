/// A frame-carrying connection to a headset. The session drives one of these; the Bluetooth
/// channel implements it, and tests substitute their own.
public protocol MDRLink: AnyObject {
    var onOpen: (() -> Void)? { get set }
    var onFrame: ((MDRFrame) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }

    func open() throws
    func send(_ frame: MDRFrame) throws
    func close()
}
