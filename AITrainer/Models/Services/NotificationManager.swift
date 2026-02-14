//
//  NotificationManager.swift
//  AITrainer
//
//  Local and push notification management
//

import Foundation
import UserNotifications
import Combine

class NotificationManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let reminderPrefix = "reminder_"
    
    override init() {
        super.init()
        notificationCenter.delegate = self
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
            
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }
    
    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Schedule Notifications
    
    func scheduleWorkoutReminder(at date: Date, workoutName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Work Out! 💪"
        content.body = "Your \(workoutName) session is scheduled now. Let's get moving!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "WORKOUT_REMINDER"
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "workout_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling workout reminder: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleMealReminder(at date: Date, mealType: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Log Your Meal 🍽️"
        content.body = "Don't forget to log your \(mealType). Snap a quick photo!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "MEAL_REMINDER"
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "meal_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling meal reminder: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleCheckInReminder(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Check-In ✨"
        content.body = "How are you feeling today? Let's review your progress with your AI coach."
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "CHECKIN_REMINDER"
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "daily_checkin",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling check-in reminder: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleStreakReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Keep Your Streak Going! 🔥"
        content.body = "You're doing great! Don't break your streak today."
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "STREAK_REMINDER"
        
        var dateComponents = DateComponents()
        dateComponents.hour = 20 // 8 PM
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "streak_reminder",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling streak reminder: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleAISuggestionNotification(suggestion: AISuggestion) {
        let content = UNMutableNotificationContent()
        content.title = "New AI Coach Suggestion 🤖"
        content.body = suggestion.title
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "AI_SUGGESTION"
        content.userInfo = ["suggestionId": suggestion.id.uuidString]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "suggestion_\(suggestion.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling AI suggestion: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Manage Notifications
    
    func cancelNotification(withIdentifier identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        notificationCenter.getPendingNotificationRequests { requests in
            completion(requests)
        }
    }

    // MARK: - Backend Reminder Sync

    func syncReminders(_ reminders: [ReminderItemResponse], notificationsEnabled: Bool = true) {
        guard notificationsEnabled else {
            cancelReminderNotifications()
            return
        }
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        let activeReminders = reminders.filter { reminder in
            reminder.channel.lowercased() == "ios" && reminder.status.lowercased() != "cancelled"
        }

        // Replace only reminder-managed notifications; keep unrelated local notifications intact.
        getPendingNotifications { [weak self] requests in
            guard let self = self else { return }
            let existingReminderIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.reminderPrefix) }
            if !existingReminderIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: existingReminderIds)
            }

            activeReminders.forEach { self.scheduleReminderNotification(from: $0) }
        }
    }

    func cancelReminderNotifications() {
        getPendingNotifications { [weak self] requests in
            guard let self = self else { return }
            let reminderIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.reminderPrefix) }
            if !reminderIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: reminderIds)
            }
        }
    }

    func sendToggleOnTestNotification() {
        let requestTestNotification = { [weak self] in
            guard let self = self else { return }
            let content = UNMutableNotificationContent()
            content.title = "Notifications Enabled"
            content.body = "Vaylo Fitness reminders are now turned on."
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = "GENERAL_REMINDER"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "notification_toggle_test_\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            self.notificationCenter.add(request) { error in
                if let error = error {
                    print("Error scheduling toggle test notification: \(error.localizedDescription)")
                }
            }
        }

        if isAuthorized {
            requestTestNotification()
            return
        }

        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
            }
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
                return
            }
            if granted {
                requestTestNotification()
            }
        }
    }
    
    // MARK: - Badge Management
    
    func setBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Error setting badge count: \(error.localizedDescription)")
            }
        }
    }
    
    func clearBadge() {
        setBadgeCount(0)
    }

    private func scheduleReminderNotification(from reminder: ReminderItemResponse) {
        guard let date = parseReminderDate(reminder.scheduled_at) else { return }
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        let normalizedType = reminder.reminder_type.lowercased()

        if normalizedType.contains("workout") {
            content.title = "Workout Reminder"
            content.body = "Time for your planned workout. Let's keep your streak alive."
            content.categoryIdentifier = "WORKOUT_REMINDER"
        } else if normalizedType.contains("meal") {
            content.title = "Meal Reminder"
            content.body = "Time to log your meal and stay on target."
            content.categoryIdentifier = "MEAL_REMINDER"
        } else {
            content.title = "Fitness Reminder"
            content.body = "You have a scheduled reminder in Vaylo Fitness."
            content.categoryIdentifier = "GENERAL_REMINDER"
        }

        content.sound = .default
        content.badge = 1

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(reminderPrefix)\(reminder.id)",
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling reminder notification \(reminder.id): \(error.localizedDescription)")
            }
        }
    }

    private func parseReminderDate(_ raw: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone.current
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: raw)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        
        switch categoryIdentifier {
        case "WORKOUT_REMINDER":
            // Navigate to workout screen
            print("User tapped workout reminder")
        case "MEAL_REMINDER":
            // Open food scanner
            print("User tapped meal reminder")
        case "AI_SUGGESTION":
            // Open AI coach
            print("User tapped AI suggestion")
        default:
            break
        }
        
        completionHandler()
    }
}
