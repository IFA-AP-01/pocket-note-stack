import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var references: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    var onNewNote: (() -> Void)?
    var onAllNotes: (() -> Void)?
    var onArchive: (() -> Void)?

    func registerDefaults() {
        unregisterAll()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(pointer).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout.size(ofValue: id), nil, &id)
            Task { @MainActor in
                switch id.id {
                case 1: manager.onNewNote?()
                case 2: manager.onAllNotes?()
                case 3: manager.onArchive?()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        register(id: 1, key: UInt32(kVK_ANSI_N))
        register(id: 2, key: UInt32(kVK_ANSI_A))
        register(id: 3, key: UInt32(kVK_ANSI_L))
    }

    func unregisterAll() {
        references.forEach { if let value = $0 { UnregisterEventHotKey(value) } }
        references.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    private func register(id: UInt32, key: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5053544B), id: id)
        RegisterEventHotKey(key, UInt32(cmdKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &reference)
        references.append(reference)
    }
}
