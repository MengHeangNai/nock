import AppKit

/// An active event tap on the volume, brightness and keyboard backlight keys, on the main run loop. The handler returns true to consume a press, which keeps macOS from acting on it and showing its own overlay. The tap sits at the HID level, where key events enter the window server.
final class MediaKeyTap {
    private static let systemDefinedEvent = CGEventType(rawValue: 14)!

    private let handler: (MediaKeyPress) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { port != nil }

    init(handler: @escaping (MediaKeyPress) -> Bool) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Returns false when macOS refuses the tap, which happens until Accessibility is allowed.
    func start() -> Bool {
        guard port == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue().receive(type, event)
        }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: 1 << Self.systemDefinedEvent.rawValue, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefinedEvent, let system = NSEvent(cgEvent: event),
              let press = MediaKeyPress(subtype: Int(system.subtype.rawValue), data1: system.data1,
                                        modifiers: MediaKeyModifiers(event.flags)) else { return Unmanaged.passUnretained(event) }
        return handler(press) ? nil : Unmanaged.passUnretained(event)
    }
}

extension MediaKeyModifiers {
    init(_ flags: CGEventFlags) {
        var modifiers: MediaKeyModifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        self = modifiers
    }
}
