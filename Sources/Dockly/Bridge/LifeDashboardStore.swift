import Foundation
import Combine

// Polls the life-dashboard backend for tasks + upcoming events and publishes
// them for the Tasks tab. Degrades gracefully when the backend is offline.
@MainActor
final class LifeDashboardStore: ObservableObject {
    static let shared = LifeDashboardStore()

    @Published private(set) var tasks: [LDTask] = []
    @Published private(set) var events: [LDEvent] = []
    @Published private(set) var online = false
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() {
        Task { await refresh() }
    }

    /// Optimistically remove the task locally, then POST completion to backend.
    func complete(_ task: LDTask) {
        tasks.removeAll { $0.id == task.id }
        Task {
            let ok = await LifeDashboardBridge.shared.completeTask(id: task.id)
            if !ok { await refresh() }   // revert/resync if backend rejected
        }
    }

    func refresh() async {
        let available = await LifeDashboardBridge.shared.isAvailable()
        guard available else {
            online = false
            return
        }
        online = true
        do {
            let t = try await LifeDashboardBridge.shared.fetchTasks()
            let e = try await LifeDashboardBridge.shared.fetchUpcomingEvents()
            tasks = t
            events = e
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
