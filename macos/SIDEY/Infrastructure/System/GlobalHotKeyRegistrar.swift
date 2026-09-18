import Carbon.HIToolbox

struct GlobalHotKeyRegistration: Hashable, Sendable {
    let id: UInt32
}

struct GlobalHotKeyRegistrationError: Error, Equatable, Sendable {
    let status: OSStatus
}

/// Registers only the exact combinations the user assigned. macOS reports presses of
/// those combinations; SIDEY never observes other keyboard input and needs no
/// Accessibility or Input Monitoring permission.
@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
    func register(
        _ shortcut: GlobalShortcut,
        onPress: @escaping () -> Void
    ) -> Result<GlobalHotKeyRegistration, GlobalHotKeyRegistrationError>
    func unregister(_ registration: GlobalHotKeyRegistration)
}

@MainActor
final class CarbonGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    /// "SIDY"
    nonisolated static let signature: OSType = 0x5349_4459

    // The C callback cannot capture context, so presses are routed by hot-key identifier.
    private static var eventHandler: EventHandlerRef?
    private static var nextIdentifier: UInt32 = 0
    private static var pressHandlers: [UInt32: () -> Void] = [:]
    private var hotKeys: [GlobalHotKeyRegistration: EventHotKeyRef] = [:]

    func register(
        _ shortcut: GlobalShortcut,
        onPress: @escaping () -> Void
    ) -> Result<GlobalHotKeyRegistration, GlobalHotKeyRegistrationError> {
        let handlerStatus = Self.installEventHandlerIfNeeded()
        guard handlerStatus == noErr else {
            return .failure(GlobalHotKeyRegistrationError(status: handlerStatus))
        }
        Self.nextIdentifier &+= 1
        let identifier = Self.nextIdentifier
        var outRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.rawValue,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(),
            0,
            &outRef
        )
        guard status == noErr, let hotKeyRef = outRef else {
            return .failure(GlobalHotKeyRegistrationError(status: status))
        }
        let registration = GlobalHotKeyRegistration(id: identifier)
        hotKeys[registration] = hotKeyRef
        Self.pressHandlers[identifier] = onPress
        return .success(registration)
    }

    func unregister(_ registration: GlobalHotKeyRegistration) {
        Self.pressHandlers[registration.id] = nil
        guard let hotKeyRef = hotKeys.removeValue(forKey: registration) else { return }
        UnregisterEventHotKey(hotKeyRef)
    }

    fileprivate static func handlePress(identifier: UInt32) -> Bool {
        guard let handler = pressHandlers[identifier] else { return false }
        handler()
        return true
    }

    private static func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandler == nil else { return OSStatus(noErr) }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handleGlobalHotKeyEvent,
            1,
            &eventType,
            nil,
            &handler
        )
        if status == noErr {
            eventHandler = handler
        }
        return status
    }
}

/// Hot-key events arrive on the main event loop and carry only the registered identifier.
private func handleGlobalHotKeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == CarbonGlobalHotKeyRegistrar.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let identifier = hotKeyID.id
    let handled = MainActor.assumeIsolated {
        CarbonGlobalHotKeyRegistrar.handlePress(identifier: identifier)
    }
    return handled ? OSStatus(noErr) : OSStatus(eventNotHandledErr)
}
