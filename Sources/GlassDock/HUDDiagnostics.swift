import AppKit // TEMP-HUD-DIAG
import os // TEMP-HUD-DIAG
// TEMP-HUD-DIAG
enum HUDDiag { // TEMP-HUD-DIAG
    private static let logger = Logger(subsystem: "local.glassdock.nodock", category: "hud") // TEMP-HUD-DIAG
    private static let loggedKeyCodes: Set<Int64> = [120, 122, 109, 103, 111, 107, 113, 144, 145] // TEMP-HUD-DIAG
    static let keyEventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) // TEMP-HUD-DIAG
    // TEMP-HUD-DIAG
    static func note(_ message: String) { // TEMP-HUD-DIAG
        logger.notice("\(message, privacy: .public)") // TEMP-HUD-DIAG
    } // TEMP-HUD-DIAG
    // TEMP-HUD-DIAG
    static func raw(_ type: CGEventType, _ event: CGEvent) { // TEMP-HUD-DIAG
        let flags = String(event.flags.rawValue, radix: 16) // TEMP-HUD-DIAG
        let sessionFlags = String(CGEventSource.flagsState(.combinedSessionState).rawValue, radix: 16) // TEMP-HUD-DIAG
        switch type { // TEMP-HUD-DIAG
        case .keyDown, .keyUp: // TEMP-HUD-DIAG
            let code = event.getIntegerValueField(.keyboardEventKeycode) // TEMP-HUD-DIAG
            guard loggedKeyCodes.contains(code) else { return } // TEMP-HUD-DIAG
            note("event \(type == .keyDown ? "keyDown" : "keyUp") keyCode=\(code) autorepeat=\(event.getIntegerValueField(.keyboardEventAutorepeat)) flags=0x\(flags) sessionFlags=0x\(sessionFlags)") // TEMP-HUD-DIAG
        case CGEventType(rawValue: 14)!: // TEMP-HUD-DIAG
            guard let system = NSEvent(cgEvent: event) else { return } // TEMP-HUD-DIAG
            let data1 = system.data1 // TEMP-HUD-DIAG
            note("event systemDefined subtype=\(system.subtype.rawValue) data1=0x\(String(data1, radix: 16)) key=\((data1 & 0xFFFF_0000) >> 16) state=0x\(String((data1 & 0xFF00) >> 8, radix: 16)) repeat=\(data1 & 1) flags=0x\(flags) sessionFlags=0x\(sessionFlags)") // TEMP-HUD-DIAG
        default: // TEMP-HUD-DIAG
            break // TEMP-HUD-DIAG
        } // TEMP-HUD-DIAG
    } // TEMP-HUD-DIAG
    // TEMP-HUD-DIAG
    static func decision(_ press: MediaKeyPress, consumed: Bool) { // TEMP-HUD-DIAG
        let reason = consumed ? "handled" : (press.isLeftToSystem ? "modifiers left to macOS" : "action unavailable") // TEMP-HUD-DIAG
        note("decision \(consumed ? "CONSUMED" : "PASSED") key=\(press.key) down=\(press.isDown) repeat=\(press.isRepeat) modifiers=\(press.modifiers.rawValue) reason=\(reason)") // TEMP-HUD-DIAG
    } // TEMP-HUD-DIAG
} // TEMP-HUD-DIAG
