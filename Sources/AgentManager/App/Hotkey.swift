import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey, registered through Carbon.
///
/// This is the one route that needs no Accessibility permission: an
/// `NSEvent` global monitor would, and asking for accessibility rights to open
/// a panel is a poor trade. It exists because macOS drops menu bar items when
/// the bar overflows — screen recording alone is enough — and when that
/// happens the app has no other way in.
final class Hotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Option-Command-A by default: unclaimed by macOS and by the terminals
    /// these agents run in.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_A),
         modifiers: UInt32 = UInt32(optionKey | cmdKey),
         action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == Hotkey.signature else { return noErr }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.action() }
            return noErr
        }, 1, &spec, context, &handler)

        let id = EventHotKeyID(signature: Hotkey.signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static let signature: OSType = 0x414D4752 // 'AMGR'
}
