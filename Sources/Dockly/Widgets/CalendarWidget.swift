import SwiftUI
import EventKit

final class CalendarStore: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var status: EKAuthorizationStatus = .notDetermined

    private let ek = EKEventStore()

    init() { checkAndLoad() }

    func checkAndLoad() {
        let s = EKEventStore.authorizationStatus(for: .event)
        status = s

        let granted = s == .authorized || (s.rawValue == 4) // 4 == .fullAccess (macOS 14+)
        if granted {
            loadEvents()
        } else if s == .notDetermined {
            requestAccess()
        }
    }

    private func requestAccess() {
        ek.requestAccess(to: .event) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                if granted { self?.loadEvents() }
            }
        }
    }

    private func loadEvents() {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let pred = ek.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = ek.events(matching: pred)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { $0 }
    }
}

struct CalendarWidget: View {
    @StateObject private var store = CalendarStore()

    var body: some View {
        WidgetShell(title: "upcoming") {
            switch store.status {
            case .denied, .restricted:
                Label("Calendar access denied", systemImage: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            default:
                if store.events.isEmpty {
                    Text("Nothing coming up")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.events, id: \.eventIdentifier) { event in
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
        .frame(width: 210)
    }
}

struct EventRowView: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(event.startDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
