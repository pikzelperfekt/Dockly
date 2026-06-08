import SwiftUI

struct DocklyTask: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
}

final class TasksStore: ObservableObject {
    @Published var tasks: [DocklyTask] = []

    private let key = "dockly.tasks"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DocklyTask].self, from: data) else { return }
        tasks = decoded
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tasks.insert(DocklyTask(title: trimmed), at: 0)
        save()
    }

    func toggle(_ task: DocklyTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].done.toggle()
        save()
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    var pending: [DocklyTask] { tasks.filter { !$0.done }.prefix(6).map { $0 } }
}

struct TasksWidget: View {
    @StateObject private var store = TasksStore()
    @State private var draft = ""

    var body: some View {
        WidgetShell(title: "tasks") {
            VStack(alignment: .leading, spacing: 5) {
                if store.pending.isEmpty {
                    Text("All clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.pending) { task in
                    HStack(spacing: 7) {
                        Button { store.toggle(task) } label: {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)

                        Text(task.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }

                // Inline add
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    TextField("Add task…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .onSubmit {
                            store.add(draft)
                            draft = ""
                        }
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 190)
    }
}
