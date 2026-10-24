import Cocoa
import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()
    
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    
    enum HotKeyAction: UInt32 {
        case toggleHUD1 = 1 // ⌘⌥Space
        case toggleHUD2 = 2 // ⌃⌥Space
        case snapLeft = 3   // ⌘⇧← (Repeated cycle: 1/2 -> 2/3 -> 1/3)
        case snapRight = 4  // ⌘⇧→ (Repeated cycle: 1/2 -> 2/3 -> 1/3)
        case snapMax = 5    // ⌘⇧↑ (Repeated cycle: Max -> Top -> Bottom)
        case snapCenter = 6 // ⌘⇧↓ (Repeated cycle: Mid -> Large -> Small)
        case throwNext = 7  // ⌃⌥⌘→ (Throw to Next Screen)
        case throwPrev = 8  // ⌃⌥⌘← (Throw to Prev Screen)
    }
    
    private init() {}
    
    func start() {
        stop()
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
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
                if status == noErr {
                    DispatchQueue.main.async {
                        HotKeyManager.shared.handleHotKey(id: hotKeyID.id)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            observer,
            &eventHandler
        )
        
        if handlerStatus != noErr {
            NSLog("[Lattice] Failed to install Carbon event handler: \(handlerStatus)")
        }
        
        // 1. ⌘⌥Space (Cmd + Option + Space: keyCode 49)
        register(id: .toggleHUD1, keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
        // 2. ⌃⌥Space (Ctrl + Option + Space: keyCode 49)
        register(id: .toggleHUD2, keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        // 3. ⌘⇧← (Cmd + Shift + Left Arrow: keyCode 123)
        register(id: .snapLeft, keyCode: 123, modifiers: UInt32(cmdKey | shiftKey))
        // 4. ⌘⇧→ (Cmd + Shift + Right Arrow: keyCode 124)
        register(id: .snapRight, keyCode: 124, modifiers: UInt32(cmdKey | shiftKey))
        // 5. ⌘⇧↑ (Cmd + Shift + Up Arrow: keyCode 126)
        register(id: .snapMax, keyCode: 126, modifiers: UInt32(cmdKey | shiftKey))
        // 6. ⌘⇧↓ (Cmd + Shift + Down Arrow: keyCode 125)
        register(id: .snapCenter, keyCode: 125, modifiers: UInt32(cmdKey | shiftKey))
        // 7. ⌃⌥⌘→ (Ctrl + Option + Cmd + Right Arrow: keyCode 124)
        register(id: .throwNext, keyCode: 124, modifiers: UInt32(controlKey | optionKey | cmdKey))
        // 8. ⌃⌥⌘← (Ctrl + Option + Cmd + Left Arrow: keyCode 123)
        register(id: .throwPrev, keyCode: 123, modifiers: UInt32(controlKey | optionKey | cmdKey))
        
        NSLog("[Lattice] Carbon HotKeyManager successfully registered all hotkeys.")
    }
    
    private func register(id: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: 0x4C415454, id: id.rawValue) // 'LATT'
        var hotKeyRef: EventHotKeyRef?
        let err = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if err == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        } else {
            NSLog("[Lattice] Failed to register hotkey \(id): \(err)")
        }
    }
    
    func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eh = eventHandler {
            RemoveEventHandler(eh)
            eventHandler = nil
        }
    }
    
    func handleHotKey(id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else { return }
        LogDebug("handleHotKey: \(action)")
        switch action {
        case .toggleHUD1, .toggleHUD2:
            GridHUDController.shared.toggleHUD()
        case .snapLeft:
            WindowManager.shared.snapLeftHalf()
        case .snapRight:
            WindowManager.shared.snapRightHalf()
        case .snapMax:
            WindowManager.shared.snapMaximize()
        case .snapCenter:
            WindowManager.shared.snapCenterSmall()
        case .throwNext:
            WindowManager.shared.throwToNextScreen()
        case .throwPrev:
            WindowManager.shared.throwToPrevScreen()
        }
    }
}
