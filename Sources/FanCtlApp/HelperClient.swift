import Foundation
import FanCtlProtocol
import os.log

private let log = Logger(subsystem: "com.juanipis.FanCtl", category: "HelperClient")

/// XPC client for FanCtlHelper. Not `@MainActor`-isolated as a whole — the
/// XPC reply blocks fire on `NSXPCConnection`'s internal queue, so we hop
/// to main with `DispatchQueue.main.async` before mutating @Published state.
/// `connection`, `pollTimer`, `heartbeatTimer` are touched from main only.
/// One sample retained for the live sparkline. Codable so the ring buffer
/// can be persisted across launches — the chart shouldn't be blank every
/// time the user reopens the popover.
struct HistorySample: Identifiable, Hashable, Codable {
    var id = UUID()
    let timestamp: Date
    let rpm: Double
    let hottestC: Double

    private enum CodingKeys: String, CodingKey { case timestamp, rpm, hottestC }
}

final class HelperClient: ObservableObject, @unchecked Sendable {

    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var lastError: String?
    @Published private(set) var isConnected: Bool = false
    /// True when the running helper rejected a feature this app version
    /// knows about — almost always means launchd is still running the
    /// previous helper binary and needs to be kicked.
    @Published private(set) var helperOutOfDate: Bool = false
    /// 60-sample ring buffer (~1 minute at 1 Hz polling), persisted to
    /// UserDefaults so the sparkline survives a quit/relaunch.
    @Published private(set) var history: [HistorySample] = []
    private let historyCap = 60
    private let historyKey = "com.juanipis.FanCtl.history"
    /// Drop persisted samples older than this — no point restoring a chart
    /// from yesterday.
    private let historyMaxAge: TimeInterval = 5 * 60

    private var connection: NSXPCConnection?
    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?

    init() {
        loadHistory()
        connect()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let samples = try? JSONDecoder().decode([HistorySample].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-historyMaxAge)
        history = samples.filter { $0.timestamp >= cutoff }.suffix(historyCap)
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    /// Tear down any existing channel and open a fresh one. Call after
    /// the helper is (re)installed via SMAppService.
    func reconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
        connect()
        refresh()
    }

    func connect() {
        let conn = NSXPCConnection(
            machServiceName: kHelperMachServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: FanCtlHelperXPC.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.lastError = "Helper invalidated. Re-install via Settings."
                log.error("XPC invalidated")
            }
        }
        conn.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.isConnected = false
                log.notice("XPC interrupted")
            }
        }
        conn.resume()
        self.connection = conn

        proxy()?.ping { [weak self] msg in
            DispatchQueue.main.async {
                self?.isConnected = true
                self?.lastError = nil
                log.info("Helper said: \(msg, privacy: .public)")
            }
        }
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.proxy()?.heartbeat { }
        }
        refresh()
    }

    func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
    }

    func refresh() {
        proxy()?.snapshot { [weak self] data, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data,
                   let snap = try? JSONDecoder().decode(SystemSnapshot.self, from: data) {
                    self.snapshot = snap
                    self.lastError = nil
                    self.isConnected = true
                    let rpm = snap.fans.first?.current ?? 0
                    self.history.append(HistorySample(
                        timestamp: snap.timestamp,
                        rpm: rpm,
                        hottestC: snap.hottestC
                    ))
                    if self.history.count > self.historyCap {
                        self.history.removeFirst(self.history.count - self.historyCap)
                    }
                    self.persistHistory()
                    Notifications.shared.observe(snap)
                } else if let err {
                    self.lastError = err
                }
            }
        }
    }

    func setMode(_ mode: ControlMode) {
        proxy()?.setMode(modeId: mode.rawValue) { [weak self] err in
            DispatchQueue.main.async {
                if let err {
                    self?.lastError = err
                    // "unknown mode: …" means we're talking to a helper
                    // older than this app — surface the dedicated banner
                    // instead of a raw error string.
                    if err.lowercased().contains("unknown mode") {
                        self?.helperOutOfDate = true
                        self?.lastError = nil
                    }
                }
                self?.refresh()
            }
        }
    }

    /// Clears the `helperOutOfDate` flag — call after the user restarts
    /// the helper so the banner disappears.
    func clearOutOfDateFlag() { helperOutOfDate = false }

    func setManual(fan: Int, rpm: Double) {
        proxy()?.setManual(fan: fan, rpm: rpm) { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = err }
                self?.refresh()
            }
        }
    }

    func setAuto(fan: Int) {
        proxy()?.setAuto(fan: fan) { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = err }
                self?.refresh()
            }
        }
    }

    func setAllAuto() {
        proxy()?.setAllAuto { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = err }
                self?.refresh()
            }
        }
    }

    func setCustomCurve(_ curve: FanCurve) {
        guard let data = try? JSONEncoder().encode(curve) else { return }
        proxy()?.setCustomCurve(curveData: data) { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = err }
                self?.refresh()
            }
        }
    }

    func setSensorKey(_ key: String?) {
        proxy()?.setSensorKey(key: key) { [weak self] err in
            DispatchQueue.main.async {
                if let err { self?.lastError = err }
                self?.refresh()
            }
        }
    }

    private func proxy() -> FanCtlHelperXPC? {
        guard let conn = connection else { return nil }
        return conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = "\(error.localizedDescription)"
                self?.isConnected = false
            }
        } as? FanCtlHelperXPC
    }
}
