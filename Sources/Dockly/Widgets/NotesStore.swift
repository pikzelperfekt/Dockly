import Foundation
import Combine

final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published var text: String {
        didSet { scheduleSave() }
    }

    private var saveTimer: Timer?

    private init() {
        text = UserDefaults.standard.string(forKey: "dockly_notes") ?? ""
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            UserDefaults.standard.set(self?.text, forKey: "dockly_notes")
        }
    }
}
