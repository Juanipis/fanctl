import Foundation

/// Mach service name the helper registers and the app connects to.
public let kHelperMachServiceName = "com.jpdiaz.FanCtl.Helper"

/// LaunchDaemon plist file (lives at Contents/Library/LaunchDaemons/<name>).
public let kHelperPlistName = "com.jpdiaz.FanCtl.Helper.plist"

// MARK: - Control modes

/// One of five fan control modes. Only `auto` and `manual` go straight to
/// the SMC unchanged; the curve modes have the helper run a 2 Hz loop that
/// maps the hottest temperature to a target RPM.
public enum ControlMode: String, Codable, CaseIterable, Sendable {
    case auto         // F<n>md = 0; macOS owns the fans
    case silent       // gentle curve: keep RPM low
    case cool         // moderate curve: keep temps low
    case performance  // aggressive curve: ramp early
    case manual       // F<n>md = 1; app sends explicit target

    public var displayName: String {
        switch self {
        case .auto:        return "Auto"
        case .silent:      return "Silent"
        case .cool:        return "Cool"
        case .performance: return "Perf"
        case .manual:      return "Manual"
        }
    }

    public var symbolName: String {
        switch self {
        case .auto:        return "wand.and.stars"
        case .silent:      return "moon.zzz"
        case .cool:        return "snowflake"
        case .performance: return "bolt.fill"
        case .manual:      return "slider.horizontal.3"
        }
    }

    /// Built-in curve definition for the curve modes. `auto` and `manual`
    /// return `nil`. Curve points are `(temperatureC, rpmFraction 0..1)`,
    /// ascending in temperature; the helper interpolates linearly between
    /// breakpoints and clamps to `[0, 1]`.
    public var curve: FanCurve? {
        switch self {
        case .auto, .manual:
            return nil
        case .silent:
            return FanCurve(points: [
                .init(tempC: 50, rpmFraction: 0.0),
                .init(tempC: 75, rpmFraction: 0.5),
                .init(tempC: 90, rpmFraction: 1.0),
            ])
        case .cool:
            return FanCurve(points: [
                .init(tempC: 40, rpmFraction: 0.0),
                .init(tempC: 60, rpmFraction: 0.5),
                .init(tempC: 75, rpmFraction: 1.0),
            ])
        case .performance:
            return FanCurve(points: [
                .init(tempC: 35, rpmFraction: 0.5),
                .init(tempC: 50, rpmFraction: 1.0),
            ])
        }
    }
}

public struct FanCurve: Codable, Sendable, Hashable {
    public struct Point: Codable, Sendable, Hashable {
        public var tempC: Double
        public var rpmFraction: Double  // 0…1, mapped to [F<n>Mn, F<n>Mx]
        public init(tempC: Double, rpmFraction: Double) {
            self.tempC = tempC
            self.rpmFraction = rpmFraction
        }
    }
    public var points: [Point]
    public init(points: [Point]) { self.points = points }

    /// Linearly interpolates the curve at `tempC`. Below the lowest point
    /// returns the first fraction; above the highest, the last.
    public func evaluate(tempC: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if tempC <= first.tempC { return first.rpmFraction }
        if tempC >= last.tempC  { return last.rpmFraction }
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            if tempC >= a.tempC && tempC <= b.tempC {
                let t = (tempC - a.tempC) / (b.tempC - a.tempC)
                return a.rpmFraction + t * (b.rpmFraction - a.rpmFraction)
            }
        }
        return last.rpmFraction
    }
}

// MARK: - Snapshot types

public struct FanState: Codable, Sendable, Hashable {
    public let index: Int
    public var current: Double
    public var min: Double
    public var max: Double
    public var target: Double
    public var modeRaw: UInt8

    public var isManual: Bool { modeRaw == 1 }

    public init(index: Int, current: Double, min: Double, max: Double, target: Double, modeRaw: UInt8) {
        self.index = index
        self.current = current
        self.min = min
        self.max = max
        self.target = target
        self.modeRaw = modeRaw
    }
}

public struct TempState: Codable, Sendable, Hashable {
    public let key: String
    public var celsius: Double

    public init(key: String, celsius: Double) {
        self.key = key
        self.celsius = celsius
    }
}

public struct SystemSnapshot: Codable, Sendable {
    public var fans: [FanState]
    public var temps: [TempState]
    public var hottestC: Double
    public var activeMode: ControlMode
    public var timestamp: Date

    public init(fans: [FanState], temps: [TempState], hottestC: Double, activeMode: ControlMode, timestamp: Date = Date()) {
        self.fans = fans
        self.temps = temps
        self.hottestC = hottestC
        self.activeMode = activeMode
        self.timestamp = timestamp
    }
}

// MARK: - XPC interface

@objc public protocol FanCtlHelperXPC {
    func ping(reply: @Sendable @escaping (String) -> Void)

    /// Reads fans + top temperatures + active mode. Reply contains
    /// JSON-encoded `SystemSnapshot`.
    func snapshot(reply: @Sendable @escaping (Data?, String?) -> Void)

    /// Switches the helper into the given control mode. `modeId` is the
    /// raw value of `ControlMode`. Setting `manual` is a no-op until the
    /// app sends an actual target via `setManual`. Setting `auto` immediately
    /// flips every fan to `F<n>md = 0`.
    func setMode(modeId: String, reply: @Sendable @escaping (String?) -> Void)

    /// Manual override: forces `manual` mode and writes target RPM. Helper
    /// clamps to `[F<n>Mn, F<n>Mx]`.
    func setManual(fan: Int, rpm: Double, reply: @Sendable @escaping (String?) -> Void)

    func setAuto(fan: Int, reply: @Sendable @escaping (String?) -> Void)
    func setAllAuto(reply: @Sendable @escaping (String?) -> Void)

    /// Heartbeat. The app pings every few seconds; if missed too long the
    /// helper forces every fan to AUTO regardless of selected mode.
    func heartbeat(reply: @Sendable @escaping () -> Void)
}
