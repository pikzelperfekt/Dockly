import Foundation
import EventKit
import AppKit

struct DayEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let colorHex: String

    var color: NSColor {
        NSColor(hex: colorHex) ?? .systemBlue
    }

    var startString: String {
        if isAllDay { return "All day" }
        return start.formatted(.dateTime.hour().minute())
    }

    var minutesUntil: Int {
        max(0, Int(start.timeIntervalSinceNow / 60))
    }
}

final class CalendarListStore: ObservableObject {
    static let shared = CalendarListStore()

    struct CalInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let colorHex: String
    }

    @Published private(set) var events: [DayEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var calendars: [CalInfo] = []

    private let ek = EKEventStore()
    private var refreshTimer: Timer?

    private init() {
        requestAccess()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized || status.rawValue == 4 {
            authorized = true
            loadCalendars()
            refresh()
            return
        }
        ek.requestAccess(to: .event) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                if granted { self?.loadCalendars(); self?.refresh() }
            }
        }
    }

    func loadCalendars() {
        guard authorized else { return }
        calendars = ek.calendars(for: .event).map {
            CalInfo(id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: NSColor(cgColor: $0.cgColor)?.hexString ?? "#3478F6")
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func refresh() {
        guard authorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let pred = ek.predicateForEvents(withStart: start, end: end, calendars: nil)
        let raw = ek.events(matching: pred)
            .sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
        events = raw.map { ev in
            DayEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Event",
                location: (ev.location?.isEmpty == false) ? ev.location : nil,
                start: ev.startDate,
                end: ev.endDate,
                isAllDay: ev.isAllDay,
                colorHex: NSColor(cgColor: ev.calendar.cgColor)?.hexString ?? "#3478F6"
            )
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let val = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#3478F6" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
