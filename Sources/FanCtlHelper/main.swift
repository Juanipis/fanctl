import Foundation
import FanCtlProtocol
import SMCKit
import os.log

let log = Logger(subsystem: "com.jpdiaz.FanCtl", category: "Helper")
let buildVersion = "0.2.0"

// MARK: - SMC backend (single shared instance, serialised via a queue)

let smcQueue = DispatchQueue(label: "com.jpdiaz.FanCtl.smc")
let smc: SMC
let fans: FanController
do {
    smc = try SMC()
    fans = FanController(smc: smc)
    log.info("Helper opened SMC via \(smc.matchedClassName, privacy: .public)")
} catch {
    log.fault("Helper could not open SMC: \(String(describing: error), privacy: .public)")
    exit(2)
}

func onSMC<T>(_ block: () throws -> T) throws -> T {
    var result: Result<T, Error>!
    smcQueue.sync {
        do { result = .success(try block()) }
        catch { result = .failure(error) }
    }
    switch result! {
    case .success(let v): return v
    case .failure(let e): throw e
    }
}

// MARK: - Mode controller (the "smart" part)

/// Owns the active `ControlMode` and runs the curve evaluator. The helper
/// decides target RPMs every 2s based on the hottest temperature and the
/// curve attached to the current mode.
final class ModeController: @unchecked Sendable {

    static let shared = ModeController()

    private let queue = DispatchQueue(label: "com.jpdiaz.FanCtl.mode")
    private var current: ControlMode
    private var timer: DispatchSourceTimer?
    private let prefsKey = "com.jpdiaz.FanCtl.activeMode"
    /// EMA-smoothed hottest temperature. Avoids jittery RPM swings when
    /// thermal sensors flicker by 1–2°C.
    private var smoothedHottestC: Double = 0
    private let smoothingAlpha: Double = 0.3

    private init() {
        // Persisted via CFPreferences in the helper's preferences domain.
        if let raw = UserDefaults.standard.string(forKey: prefsKey),
           let mode = ControlMode(rawValue: raw) {
            current = mode
        } else {
            current = .auto
        }
        log.info("ModeController booted with \(self.current.rawValue, privacy: .public)")
    }

    var mode: ControlMode {
        queue.sync { current }
    }

    func setMode(_ new: ControlMode) throws {
        queue.sync {
            current = new
            UserDefaults.standard.set(new.rawValue, forKey: prefsKey)
        }
        // Apply the mode change immediately rather than waiting for the
        // next tick — feels snappy and avoids surprise lag.
        if new == .auto {
            try onSMC { try fans.setAllAuto() }
        } else if new == .manual {
            // No-op: manual mode just stops the curve loop. The app will
            // follow up with `setManual(fan:rpm:)`.
        } else {
            applyCurveTick()
        }
        log.notice("setMode(\(new.rawValue, privacy: .public))")
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 2.0)
        t.setEventHandler { [weak self] in self?.applyCurveTick() }
        timer = t
        t.resume()
    }

    /// Reads hottest temp, evaluates curve, writes target. Called on the
    /// mode queue (which is fine — actual SMC work jumps to `smcQueue`).
    private func applyCurveTick() {
        guard let curve = current.curve else { return }
        do {
            let snap = try onSMC { () -> (Double, [FanController.Fan]) in
                let temps = fans.discoverTemperatures()
                let hottest = temps.first?.celsius ?? 0
                let f = try fans.readAllFans()
                return (hottest, f)
            }
            let raw = snap.0
            // First-sample bootstrap.
            if smoothedHottestC == 0 { smoothedHottestC = raw }
            smoothedHottestC = smoothingAlpha * raw + (1 - smoothingAlpha) * smoothedHottestC

            let frac = curve.evaluate(tempC: smoothedHottestC).clamped(to: 0...1)
            for fan in snap.1 {
                let target = fan.min + frac * (fan.max - fan.min)
                try? onSMC { try fans.setManual(fan.index, rpm: target) }
            }
        } catch {
            log.error("Curve tick failed: \(String(describing: error), privacy: .public)")
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

// MARK: - Watchdog (dead-man + thermal panic)

final class Watchdog: @unchecked Sendable {
    static let shared = Watchdog()

    private let queue = DispatchQueue(label: "com.jpdiaz.FanCtl.watchdog")
    private var lastHeartbeat: Date = .distantFuture
    private var armed: Bool = false
    private var timer: DispatchSourceTimer?

    let heartbeatTimeoutSec: TimeInterval = 12
    let thermalCapC: Double = 95

    func recordHeartbeat() { queue.sync { lastHeartbeat = Date() } }

    /// Arms once the helper observes that something is actively manipulating
    /// the fans (manual write or curve mode). Auto mode has nothing to
    /// recover from, so we don't bother arming.
    func arm() {
        queue.sync {
            if !armed {
                armed = true
                lastHeartbeat = Date()
                log.info("Watchdog armed")
            }
        }
    }

    func disarm() { queue.sync { armed = false } }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        guard armed else { return }

        let elapsed = Date().timeIntervalSince(lastHeartbeat)
        if elapsed > heartbeatTimeoutSec {
            log.error("Watchdog: heartbeat timeout (\(elapsed, format: .fixed(precision: 1))s) — forcing AUTO")
            forceAutoAndDisarm(reason: "heartbeat-timeout")
            return
        }
        let hottest = (try? onSMC { fans.discoverTemperatures().first?.celsius ?? 0 }) ?? 0
        if hottest >= thermalCapC {
            log.error("Watchdog: thermal panic (\(hottest, format: .fixed(precision: 1))°C) — forcing AUTO")
            forceAutoAndDisarm(reason: "thermal-panic")
        }
    }

    private func forceAutoAndDisarm(reason: String) {
        do {
            try ModeController.shared.setMode(.auto)
            log.notice("Watchdog: switched to AUTO (\(reason, privacy: .public))")
            armed = false
        } catch {
            log.fault("Watchdog: could not force AUTO: \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Rate limiter (≤ 2 writes per second per fan, manual mode only)

final class RateLimiter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jpdiaz.FanCtl.ratelimit")
    private var lastWriteByFan: [Int: Date] = [:]
    private let minIntervalSec: TimeInterval = 0.4

    func allow(fan: Int) -> Bool {
        queue.sync {
            let now = Date()
            if let last = lastWriteByFan[fan], now.timeIntervalSince(last) < minIntervalSec {
                return false
            }
            lastWriteByFan[fan] = now
            return true
        }
    }
}
let rateLimiter = RateLimiter()

// MARK: - XPC service

final class HelperService: NSObject, FanCtlHelperXPC {

    func ping(reply: @Sendable @escaping (String) -> Void) {
        reply("FanCtlHelper \(buildVersion)")
    }

    func snapshot(reply: @Sendable @escaping (Data?, String?) -> Void) {
        do {
            let mode = ModeController.shared.mode
            let snap: SystemSnapshot = try onSMC {
                let fanStates = try fans.readAllFans().map { f in
                    FanState(
                        index: f.index, current: f.current, min: f.min,
                        max: f.max, target: f.target, modeRaw: f.mode.rawValue
                    )
                }
                let allTemps = fans.discoverTemperatures()
                let hottest = allTemps.first?.celsius ?? 0
                let temps = allTemps.prefix(8).map { TempState(key: $0.key.description, celsius: $0.celsius) }
                return SystemSnapshot(fans: fanStates, temps: Array(temps),
                                      hottestC: hottest, activeMode: mode)
            }
            reply(try JSONEncoder().encode(snap), nil)
        } catch {
            reply(nil, "\(error)")
        }
    }

    func setMode(modeId: String, reply: @Sendable @escaping (String?) -> Void) {
        guard let mode = ControlMode(rawValue: modeId) else {
            reply("unknown mode: \(modeId)"); return
        }
        do {
            try ModeController.shared.setMode(mode)
            if mode == .auto {
                Watchdog.shared.disarm()
            } else {
                Watchdog.shared.arm()
            }
            reply(nil)
        } catch {
            reply("\(error)")
        }
    }

    func setManual(fan: Int, rpm: Double, reply: @Sendable @escaping (String?) -> Void) {
        guard rateLimiter.allow(fan: fan) else { reply("rate limited"); return }
        do {
            // Force manual mode if not already there — slider implies it.
            if ModeController.shared.mode != .manual {
                try ModeController.shared.setMode(.manual)
            }
            try onSMC { try fans.setManual(fan, rpm: rpm) }
            Watchdog.shared.arm()
            log.notice("setManual(fan=\(fan), rpm=\(rpm, format: .fixed(precision: 0)))")
            reply(nil)
        } catch {
            reply("\(error)")
        }
    }

    func setAuto(fan: Int, reply: @Sendable @escaping (String?) -> Void) {
        do {
            try ModeController.shared.setMode(.auto)
            log.notice("setAuto(fan=\(fan))")
            reply(nil)
        } catch {
            reply("\(error)")
        }
    }

    func setAllAuto(reply: @Sendable @escaping (String?) -> Void) {
        do {
            try ModeController.shared.setMode(.auto)
            log.notice("setAllAuto")
            reply(nil)
        } catch {
            reply("\(error)")
        }
    }

    func heartbeat(reply: @Sendable @escaping () -> Void) {
        Watchdog.shared.recordHeartbeat()
        reply()
    }
}

// MARK: - NSXPCListener

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let interface = NSXPCInterface(with: FanCtlHelperXPC.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = HelperService()
        newConnection.invalidationHandler = { [weak newConnection] in
            log.info("XPC connection invalidated (pid=\(newConnection?.processIdentifier ?? -1))")
            // We do NOT auto-AUTO here: the user may have selected a curve
            // mode and quit the app, expecting the helper to keep running
            // it. The dead-man watchdog only triggers if heartbeats stop
            // AND the watchdog was armed.
        }
        newConnection.interruptionHandler = { [weak newConnection] in
            log.info("XPC connection interrupted (pid=\(newConnection?.processIdentifier ?? -1))")
        }
        newConnection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: kHelperMachServiceName)
listener.delegate = delegate

ModeController.shared.start()
// Re-arm watchdog if we booted into a non-auto mode (helper restarted after
// crash with persisted curve mode — we still want a heartbeat).
if ModeController.shared.mode != .auto {
    Watchdog.shared.arm()
}
Watchdog.shared.start()
listener.resume()
log.info("FanCtlHelper \(buildVersion, privacy: .public) listening on \(kHelperMachServiceName, privacy: .public)")
RunLoop.current.run()
