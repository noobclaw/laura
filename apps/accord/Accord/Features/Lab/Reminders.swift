import Foundation
import UserNotifications

/// Local reminders to smell a maturing batch. Asked for only when a batch is saved.
enum Reminders {
    static func schedule(_ batch: Batch) {
        let center = UNUserNotificationCenter.current()
        let id = batch.id.uuidString
        let name = batch.formulaName
        let made = batch.madeAt
        let days = batch.reminderDays
        center.removePendingNotificationRequests(withIdentifiers: (0...365).map { "\(id)-\($0)" })
        guard !days.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for day in days {
                guard let date = Calendar.current.date(byAdding: .day, value: day, to: made),
                      date > Date() else { continue }
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                comps.hour = 19
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Day \(day): smell \(name)", bundle: .l10n)
                content.body = String(localized: "Note how it has matured since you made it.", bundle: .l10n)
                content.sound = .default
                let request = UNNotificationRequest(identifier: "\(id)-\(day)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                center.add(request)
            }
        }
    }

    static func cancel(_ batch: Batch) {
        let id = batch.id.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0...365).map { "\(id)-\($0)" })
    }

    static func status(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus) }
        }
    }
}
