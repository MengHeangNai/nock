import CoreGraphics
import Foundation
import ObjectiveC

/// Built-in display brightness through the private DisplayServices framework, which has no public replacement. Every call fails softly when the framework or a symbol is missing.
enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: GetFunction, set: SetFunction)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(get, to: GetFunction.self), unsafeBitCast(set, to: SetFunction.self))
    }()

    /// Nil when the display has no brightness macOS can change (most external monitors).
    static func read(_ display: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let functions else { return nil }
        let status = functions.get(display, &value)
        HUDDiag.note("DisplayServicesGetBrightness display=\(display) status=\(status) value=\(value)") // TEMP-HUD-DIAG
        return status == 0 ? value : nil
    }

    @discardableResult
    static func write(_ value: Float, to display: CGDirectDisplayID) -> Bool {
        guard let functions else { return false }
        let status = functions.set(display, min(max(value, 0), 1))
        HUDDiag.note("DisplayServicesSetBrightness display=\(display) value=\(value) status=\(status) readback=\(String(describing: read(display)))") // TEMP-HUD-DIAG
        return status == 0
    }
}

/// Keyboard backlight through the private CoreBrightness framework. `init` returns nil on Macs without a backlit keyboard.
final class KeyboardBacklight {
    private typealias GetMethod = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetMethod = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool

    private let client: NSObject
    private let keyboardID: UInt64
    private let getMethod: GetMethod
    private let setMethod: SetMethod

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        guard client.responds(to: Self.getSelector), client.responds(to: Self.setSelector),
              client.responds(to: Self.idsSelector),
              let ids = client.perform(Self.idsSelector)?.takeUnretainedValue() as? [NSNumber],
              let id = ids.first,
              let get = client.method(for: Self.getSelector), let set = client.method(for: Self.setSelector) else { return nil }
        self.client = client
        keyboardID = id.uint64Value
        getMethod = unsafeBitCast(get, to: GetMethod.self)
        setMethod = unsafeBitCast(set, to: SetMethod.self)
    }

    func read() -> Float {
        getMethod(client, Self.getSelector, keyboardID)
    }

    @discardableResult
    func write(_ value: Float) -> Bool {
        setMethod(client, Self.setSelector, min(max(value, 0), 1), keyboardID).boolValue
    }
}
