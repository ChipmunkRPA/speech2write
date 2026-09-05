import Foundation
import UserNotifications

enum NotificationService {
    enum UserInfoKey {
        static let kind = "kind"
    }

    enum Kind {
        static let aiProcessingFallback = "aiProcessingFallback"
        static let secureInputBlocked = "secureInputBlocked"
    }

    /// Shown when dictation output is suppressed because a secure input field
    /// (password entry) has keyboard focus.
    static func showSecureInputBlocked() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverSecureInputBlocked(using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.deliverSecureInputBlocked(using: center)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func deliverSecureInputBlocked(using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Dictation not inserted"
        content.body = "A secure field (password entry) has focus. Speech2Write does not type into secure fields."
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.secureInputBlocked]

        let request = UNNotificationRequest(
            identifier: "secure-input-blocked-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show secure-input notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }

    static func showAIProcessingFallback(error: String) {
        guard SettingsStore.shared.notifyAIProcessingFailures else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.deliverAIProcessingFallback(error: error, using: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, requestError in
                    if let requestError {
                        DebugLogger.shared.warning(
                            "Notification permission request failed: \(requestError.localizedDescription)",
                            source: "NotificationService"
                        )
                    }
                    guard granted else { return }
                    self.deliverAIProcessingFallback(error: error, using: center)
                }
            case .denied:
                DebugLogger.shared.debug(
                    "Skipping AI fallback notification because notification permission is denied",
                    source: "NotificationService"
                )
            @unknown default:
                break
            }
        }
    }

    private static func deliverAIProcessingFallback(error: String, using center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "AI Enhancement failed"
        content.body = "Typed raw transcription instead."
        content.subtitle = error
        content.sound = nil
        content.userInfo = [UserInfoKey.kind: Kind.aiProcessingFallback]

        let request = UNNotificationRequest(
            identifier: "ai-cleanup-fallback-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { addError in
            if let addError {
                DebugLogger.shared.warning(
                    "Failed to show AI fallback notification: \(addError.localizedDescription)",
                    source: "NotificationService"
                )
            }
        }
    }
}
