import Foundation
import UserNotifications
import FanCtlProtocol
import os.log

private let log = Logger(subsystem: "com.juanipis.FanCtl", category: "Notifications")

/// Watches successive snapshots and fires `UNUserNotifications` for two
/// classes of event:
///
/// 1. **Thermal warning** — hottest temperature crossed `warnAtC` (default
///    90 °C). Fires once per cooldown window so we don't spam.
/// 2. **Watchdog forced auto** — the active mode silently flipped from
///    a curve mode to `.auto`, which only happens when the helper's
///    watchdog kicks in (heartbeat timeout or thermal panic).
///
/// Lives entirely in the app process — launch daemons can't post
/// notifications under modern macOS.
@MainActor
final class Notifications {
    static let shared = Notifications()

    private let center = UNUserNotificationCenter.current()
    private var lastWarnAt: Date = .distantPast
    private let warnCooldown: TimeInterval = 5 * 60       // 5 min
    private var lastSeenMode: ControlMode?
    private let warnAtC: Double = 90.0

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("notification auth: \(String(describing: error), privacy: .public)")
            } else {
                log.info("notification auth granted=\(granted)")
            }
        }
    }

    func observe(_ snap: SystemSnapshot) {
        // Thermal warning
        if snap.hottestC >= warnAtC,
           Date().timeIntervalSince(lastWarnAt) > warnCooldown {
            post(
                title: "FanCtl: high temperature",
                body: String(format: "Hottest sensor is %.0f °C. Helper will fall back to auto if it climbs further.", snap.hottestC)
            )
            lastWarnAt = Date()
        }

        // Watchdog kick-in: a curve mode silently flipped to .auto.
        if let prev = lastSeenMode,
           prev != .auto, prev != .manual,
           snap.activeMode == .auto {
            post(
                title: "FanCtl: switched to Auto",
                body: "The watchdog returned control to macOS — likely because the helper missed heartbeats or temperatures climbed too high."
            )
        }
        lastSeenMode = snap.activeMode
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "fanctl-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                log.error("post failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
