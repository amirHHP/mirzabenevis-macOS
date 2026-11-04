import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var hasCalendarAccess = false
    @Published private(set) var currentEvent: EKEvent?
    @Published private(set) var upcomingEvents: [EKEvent] = []

    private let eventStore = EKEventStore()

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            hasCalendarAccess = (status == .fullAccess)
        } else {
            hasCalendarAccess = (status == .authorized)
        }
        if hasCalendarAccess {
            refreshEvents()
        }
    }

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                hasCalendarAccess = granted
                if granted {
                    refreshEvents()
                }
                return granted
            } catch {
                print("[CalendarService] Access request error: \(error)")
                hasCalendarAccess = false
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    Task { @MainActor in
                        self.hasCalendarAccess = granted
                        if granted {
                            self.refreshEvents()
                        }
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    func refreshEvents() {
        guard hasCalendarAccess else { return }

        let now = Date()
        let start = Calendar.current.date(byAdding: .minute, value: -15, to: now) ?? now
        let end = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        // Find active event (started <= now <= end) or starting in next 10 mins
        currentEvent = events.first { event in
            let startsSoon = event.startDate <= now.addingTimeInterval(600)
            let notEnded = event.endDate > now
            return startsSoon && notEnded
        }

        upcomingEvents = events.filter { $0.endDate > now }
    }

    func currentMeetingTitle() -> String? {
        refreshEvents()
        return currentEvent?.title
    }
}
