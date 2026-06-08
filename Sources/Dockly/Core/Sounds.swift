import AppKit

// Subtle UI sound effects. Respects a master toggle in settings.
enum Sounds {
    static func play(_ name: String, volume: Float = 0.4) {
        guard AppSettings.shared.soundEffects else { return }
        guard let s = NSSound(named: name) else { return }
        s.volume = volume
        s.play()
    }

    static func expand()    { play("Tink", volume: 0.25) }
    static func collapse()  { play("Pop", volume: 0.18) }
    static func tab()       { play("Tink", volume: 0.15) }
}
