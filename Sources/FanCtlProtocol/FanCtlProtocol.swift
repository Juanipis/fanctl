import Foundation

/// Mach service name the helper registers and the app connects to.
public let kHelperMachServiceName = "com.juanipis.FanCtl.Helper"

/// LaunchDaemon plist file (lives at Contents/Library/LaunchDaemons/<name>).
public let kHelperPlistName = "com.juanipis.FanCtl.Helper.plist"

// MARK: - Control modes

/// One of six fan control modes. `auto` and `manual` go straight to the
/// SMC unchanged; `silent`/`cool`/`performance` use built-in curves; and
/// `custom` runs a user-defined curve set via `setCustomCurve`.
public enum ControlMode: String, Codable, CaseIterable, Sendable {
    case auto         // F<n>md = 0; macOS owns the fans
    case silent       // gentle built-in curve
    case cool         // moderate built-in curve
    case performance  // aggressive built-in curve
    case custom       // user-defined curve persisted by helper
    case manual       // F<n>md = 1; app sends explicit target

    public var displayName: String {
        switch self {
        case .auto:        return "Auto"
        case .silent:      return "Silent"
        case .cool:        return "Cool"
        case .performance: return "Perf"
        case .custom:      return "Custom"
        case .manual:      return "Manual"
        }
    }

    public var symbolName: String {
        switch self {
        case .auto:        return "wand.and.stars"
        case .silent:      return "moon.zzz"
        case .cool:        return "snowflake"
        case .performance: return "bolt.fill"
        case .custom:      return "scribble.variable"
        case .manual:      return "slider.horizontal.3"
        }
    }

    /// One-line description for tooltips and accessibility hints.
    public var summary: String {
        switch self {
        case .auto:        return "macOS owns the fans."
        case .silent:      return "Quietest first; ramps only when really hot."
        case .cool:        return "Keeps the chassis cool. Fan starts earlier."
        case .performance: return "Aggressive cooling for sustained load."
        case .custom:      return "Your own curve, edited from Preferences."
        case .manual:      return "You set the target RPM with the slider."
        }
    }

    /// Compact human-readable rendering of the curve for tooltip display.
    /// Returns nil for `auto` and `manual` (no curve).
    public var curveSummary: String? {
        guard let c = curve else { return nil }
        return c.points
            .map { "\(Int($0.tempC))°C → \(Int($0.rpmFraction * 100))%" }
            .joined(separator: " · ")
    }

    /// Built-in curve definition for the curve modes. `auto`, `manual`,
    /// and `custom` return `nil` — `custom` resolves to whatever the user
    /// stored in the helper's preferences.
    public var curve: FanCurve? {
        switch self {
        case .auto, .manual, .custom:
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

extension FanCurve {
    /// Default curve seeded into the `custom` mode the first time the user
    /// opens Preferences. Mid-aggressive — sane starting point.
    public static let defaultCustom = FanCurve(points: [
        .init(tempC: 45, rpmFraction: 0.0),
        .init(tempC: 65, rpmFraction: 0.5),
        .init(tempC: 80, rpmFraction: 1.0),
    ])
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
    public var customCurve: FanCurve?
    public var sensorKey: String?    // nil = "hottest"; otherwise an SMC key like "Tp0X"
    public var timestamp: Date

    public init(
        fans: [FanState],
        temps: [TempState],
        hottestC: Double,
        activeMode: ControlMode,
        customCurve: FanCurve? = nil,
        sensorKey: String? = nil,
        timestamp: Date = Date()
    ) {
        self.fans = fans
        self.temps = temps
        self.hottestC = hottestC
        self.activeMode = activeMode
        self.customCurve = customCurve
        self.sensorKey = sensorKey
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

    /// Replaces the user's custom curve. JSON-encoded `FanCurve`. Helper
    /// persists it; selecting mode `.custom` then activates it. Sending
    /// an empty/invalid curve is a no-op.
    func setCustomCurve(curveData: Data, reply: @Sendable @escaping (String?) -> Void)

    /// Selects which sensor drives the curve evaluator. Pass nil/empty to
    /// fall back to "hottest", or an SMC key like "Tp0X". Persisted.
    func setSensorKey(key: String?, reply: @Sendable @escaping (String?) -> Void)

    /// Heartbeat. The app pings every few seconds; if missed too long the
    /// helper forces every fan to AUTO regardless of selected mode.
    func heartbeat(reply: @Sendable @escaping () -> Void)
}
