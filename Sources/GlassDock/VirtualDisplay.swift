import AppKit

final class VirtualDisplay {
    private typealias InitMode = @convention(c) (UnsafeRawPointer, Selector, UInt32, UInt32, Double) -> UnsafeMutableRawPointer?
    private typealias InitDisplay = @convention(c) (UnsafeRawPointer, Selector, AnyObject) -> UnsafeMutableRawPointer?
    private typealias ApplySettings = @convention(c) (AnyObject, Selector, AnyObject) -> ObjCBool

    private static let width: UInt32 = 2560
    private static let height: UInt32 = 1440
    private static let refreshRate = 60.0
    private static let size27InchInMillimeters = CGSize(width: 597, height: 336)

    let displayID: CGDirectDisplayID
    private let object: AnyObject

    private init(displayID: CGDirectDisplayID, object: AnyObject) {
        self.displayID = displayID
        self.object = object
    }

    var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    static func create() -> VirtualDisplay? {
        // Private API: each class and selector is checked first, so a macOS without them returns nil instead of crashing.
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let mode = makeMode(of: modeClass) else { return nil }

        let descriptor = descriptorClass.init()
        let descriptorValues: [(String, Any)] = [
            ("name", HiddenDisplayIdentity.name),
            ("vendorID", NSNumber(value: HiddenDisplayIdentity.vendorID)),
            ("productID", NSNumber(value: HiddenDisplayIdentity.productID)),
            ("serialNum", NSNumber(value: HiddenDisplayIdentity.serialNumber)),
            ("maxPixelsWide", NSNumber(value: width)),
            ("maxPixelsHigh", NSNumber(value: height)),
            ("sizeInMillimeters", NSValue(size: size27InchInMillimeters)),
            ("queue", DispatchQueue.main),
        ]
        let settings = settingsClass.init()
        guard descriptorValues.allSatisfy({ set($0.0, to: $0.1, on: descriptor) }),
              set("hiDPI", to: NSNumber(value: 0), on: settings),
              set("modes", to: [mode], on: settings),
              let display = makeDisplay(of: displayClass, descriptor: descriptor),
              let apply = implementation(of: "applySettings:", in: type(of: display), as: ApplySettings.self),
              apply(display, NSSelectorFromString("applySettings:"), settings).boolValue,
              let id = displayID(of: display) else { return nil }
        extendDesktop(id)
        return VirtualDisplay(displayID: id, object: display)
    }

    private static func displayID(of display: AnyObject) -> CGDirectDisplayID? {
        guard let object = display as? NSObject, object.responds(to: NSSelectorFromString("displayID")),
              let id = (object.value(forKey: "displayID") as? NSNumber)?.uint32Value, id != 0 else { return nil }
        return id
    }

    private static func set(_ key: String, to value: Any, on object: NSObject) -> Bool {
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard object.responds(to: NSSelectorFromString(setter)) else { return false }
        object.setValue(value, forKey: key)
        return true
    }

    private static func implementation<T>(of selector: String, in cls: AnyClass, as type: T.Type) -> T? {
        let name = NSSelectorFromString(selector)
        guard class_respondsToSelector(cls, name), let imp = class_getMethodImplementation(cls, name) else { return nil }
        return unsafeBitCast(imp, to: type)
    }

    private static func makeMode(of cls: AnyClass) -> AnyObject? {
        let name = "initWithWidth:height:refreshRate:"
        guard let initialize = implementation(of: name, in: cls, as: InitMode.self),
              let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc")),
              let result = initialize(allocated.toOpaque(), NSSelectorFromString(name), width, height, refreshRate)
        else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(result).takeRetainedValue()
    }

    private static func makeDisplay(of cls: AnyClass, descriptor: AnyObject) -> AnyObject? {
        let name = "initWithDescriptor:"
        guard let initialize = implementation(of: name, in: cls, as: InitDisplay.self),
              let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc")),
              let result = initialize(allocated.toOpaque(), NSSelectorFromString(name), descriptor)
        else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(result).takeRetainedValue()
    }

    private static func extendDesktop(_ id: CGDirectDisplayID) {
        guard CGDisplayIsInMirrorSet(id) != 0 else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay)
        if CGCompleteDisplayConfiguration(config, .forSession) != .success { CGCancelDisplayConfiguration(config) }
    }
}

final class VirtualDisplayHost {
    static let shared = VirtualDisplayHost()

    private static let pollAttempts = 10
    private static let pollInterval: UInt64 = 100_000_000

    private var display: VirtualDisplay?
    private var users: Set<String> = []

    var screen: NSScreen? { display?.screen }

    func acquire(for user: String) async -> NSScreen? {
        if display == nil { display = VirtualDisplay.create() }
        guard let display else { return nil }
        users.insert(user)
        for attempt in 0..<Self.pollAttempts {
            if let screen = display.screen { return screen }
            if attempt < Self.pollAttempts - 1 { try? await Task.sleep(nanoseconds: Self.pollInterval) }
        }
        release(user)
        return nil
    }

    func release(_ user: String) {
        users.remove(user)
        if users.isEmpty { display = nil }
    }
}
