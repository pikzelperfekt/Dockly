import Foundation

// Fetches data from the life-dashboard backend (http://localhost:3000).
// The backend needs two extra endpoints for full integration:
//   GET /api/tasks   → [{ id, text, done, dueDate? }]
//   GET /api/events/upcoming  → [{ id, title, start, end }]
// Add these to server/routes/ in the life-dashboard project.

struct LDTask: Codable, Identifiable {
    let id: String
    let text: String
    let done: Bool
    let dueDate: String?
}

struct LDEvent: Codable, Identifiable {
    let id: String
    let title: String
    let start: String
    let end: String
}

actor LifeDashboardBridge {
    static let shared = LifeDashboardBridge()

    private var baseURL: URL {
        URL(string: AppSettings.shared.lifeDashboardURL) ?? URL(string: "http://localhost:3000")!
    }

    func isAvailable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/health")
        guard let (_, resp) = try? await URLSession.shared.data(from: url) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    func fetchTasks() async throws -> [LDTask] {
        try await get("/api/tasks")
    }

    func fetchUpcomingEvents() async throws -> [LDEvent] {
        try await get("/api/events/upcoming")
    }

    /// Mark a task complete. Tries POST /api/tasks/<id>/complete.
    /// Returns true on 2xx. (Backend endpoint may need adding — see README note.)
    @discardableResult
    func completeTask(id: String) async -> Bool {
        let url = baseURL.appendingPathComponent("/api/tasks/\(id)/complete")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
