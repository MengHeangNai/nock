import AppKit

/// A private WindowServer space at the highest level, so Space switches and full-screen slides cannot carry a window along.
/// Uses private SkyLight API resolved at runtime; when any symbol is missing `init` returns nil and windows stay as they are.
/// Call `add(_:)` with a window after it is ordered front.
final class IslandSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CreateSpace = @convention(c) (Int32, Int, CFDictionary?) -> Int
    private typealias SetLevel = @convention(c) (Int32, Int, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias MoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias DestroySpace = @convention(c) (Int32, Int) -> Void
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let fullScreenSpaceType = 4
    private static let sharedSpacesDisplayIdentifier = "Main"

    private let connection: Int32
    private let space: Int
    private let addWindows: MoveWindows
    private let removeWindows: MoveWindows
    private let destroySpace: DestroySpace
    private var windowNumber: Int?

    init?() {
        guard let handle = dlopen(Self.skyLightPath, RTLD_NOW),
              let mainConnection: MainConnection = Self.symbol(handle, "CGSMainConnectionID"),
              let createSpace: CreateSpace = Self.symbol(handle, "CGSSpaceCreate"),
              let setLevel: SetLevel = Self.symbol(handle, "CGSSpaceSetAbsoluteLevel"),
              let showSpaces: ShowSpaces = Self.symbol(handle, "CGSShowSpaces"),
              let addWindows: MoveWindows = Self.symbol(handle, "CGSAddWindowsToSpaces"),
              let removeWindows: MoveWindows = Self.symbol(handle, "CGSRemoveWindowsFromSpaces"),
              let destroySpace: DestroySpace = Self.symbol(handle, "CGSSpaceDestroy")
        else { return nil }

        let connection = mainConnection()
        let space = createSpace(connection, 1, nil)
        guard space != 0 else { return nil }
        _ = setLevel(connection, space, Int32.max)
        showSpaces(connection, [space] as CFArray)

        self.connection = connection
        self.space = space
        self.addWindows = addWindows
        self.removeWindows = removeWindows
        self.destroySpace = destroySpace
    }

    deinit {
        if let windowNumber { removeWindows(connection, [windowNumber] as CFArray, [space] as CFArray) }
        destroySpace(connection, space)
    }

    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        windowNumber = window.windowNumber
        addWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }

    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let handle = dlopen(skyLightPath, RTLD_NOW),
              let mainConnection: MainConnection = symbol(handle, "CGSMainConnectionID"),
              let copySpaces: CopyManagedDisplaySpaces = symbol(handle, "CGSCopyManagedDisplaySpaces"),
              let spaces = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return spaces
    }

    static func isFullScreen(displayUUID: String, in managedDisplaySpaces: [[String: Any]]) -> Bool {
        managedDisplaySpaces.contains { display in
            guard let identifier = display["Display Identifier"] as? String,
                  identifier == sharedSpacesDisplayIdentifier || identifier.caseInsensitiveCompare(displayUUID) == .orderedSame,
                  let currentSpace = display["Current Space"] as? [String: Any]
            else { return false }
            return currentSpace["type"] as? Int == fullScreenSpaceType
        }
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
