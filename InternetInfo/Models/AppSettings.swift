import Carbon
import Foundation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let sampleInterval = "settings.sampleInterval"
        static let showLiveRatesInMenuBar = "settings.showLiveRatesInMenuBar"
        static let hotkeyKeyCode = "settings.hotkeyKeyCode"
        static let hotkeyModifiers = "settings.hotkeyModifiers"
    }

    /// Default: Option + Command + .
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_Period)
    static let defaultModifiers: UInt32 = UInt32(optionKey | cmdKey)

    private static let legacyToggleKeyCode: UInt32 = UInt32(kVK_ANSI_I)
    private static let legacyModifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

    var sampleInterval: TimeInterval {
        didSet { UserDefaults.standard.set(sampleInterval, forKey: Keys.sampleInterval) }
    }

    var showLiveRatesInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showLiveRatesInMenuBar, forKey: Keys.showLiveRatesInMenuBar) }
    }

    var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers) }
    }

    init(defaults: UserDefaults = .standard) {
        let storedInterval = defaults.object(forKey: Keys.sampleInterval) as? Double
        sampleInterval = storedInterval ?? 1
        showLiveRatesInMenuBar = defaults.object(forKey: Keys.showLiveRatesInMenuBar) as? Bool ?? false

        let storedKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode).map { _ in
            UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode))
        }
        let storedModifiers = defaults.object(forKey: Keys.hotkeyModifiers).map { _ in
            UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
        }

        let usingLegacyToggle = storedKeyCode == Self.legacyToggleKeyCode
            && storedModifiers == Self.legacyModifiers
        hotkeyKeyCode = usingLegacyToggle ? Self.defaultKeyCode : (storedKeyCode ?? Self.defaultKeyCode)
        hotkeyModifiers = usingLegacyToggle ? Self.defaultModifiers : (storedModifiers ?? Self.defaultModifiers)

        if usingLegacyToggle {
            defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
        }

        defaults.removeObject(forKey: "settings.closeHotkeyKeyCode")
        defaults.removeObject(forKey: "settings.closeHotkeyModifiers")
    }
}
