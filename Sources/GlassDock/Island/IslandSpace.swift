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

    private let connection: Int32
    private let space: Int
    private let addWindows: MoveWindows
    private let removeWindows: MoveWindows
    private let destroySpace: DestroySpace
    private var windowNumber: Int?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
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

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
}
