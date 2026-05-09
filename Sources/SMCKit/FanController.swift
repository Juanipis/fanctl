import Foundation

/// High-level fan operations on top of `SMC`. Discovers fans/temperatures
/// at runtime and centralises the SMC key naming convention.
public final class FanController: @unchecked Sendable {

    public struct Fan: Sendable, Identifiable {
        public let index: Int
        public var id: Int { index }
        public var current: Double
        public var min: Double
        public var max: Double
        public var target: Double
        public var mode: Mode

        public enum Mode: UInt8, Sendable { case auto = 0, forced = 1 }
    }

    public struct Temperature: Sendable, Identifiable {
        public let key: SMCKey
        public var celsius: Double
        public var id: SMCKey { key }
    }

    private let smc: SMC

    public init(smc: SMC) {
        self.smc = smc
    }

    /// Reads the number of fans the SMC reports (`FNum`, ui8).
    public func fanCount() throws -> Int {
        let v = try smc.read(SMCKey("FNum"))
        if case .uint8(let n) = v { return Int(n) }
        return Int(v.asDouble ?? 0)
    }

    public func readFan(_ i: Int) throws -> Fan {
        let cur = try smc.read(SMCKey("F\(i)Ac")).asDouble ?? 0
        let mn  = try smc.read(SMCKey("F\(i)Mn")).asDouble ?? 0
        let mx  = try smc.read(SMCKey("F\(i)Mx")).asDouble ?? 0
        let tg  = try smc.read(SMCKey("F\(i)Tg")).asDouble ?? 0
        let mdRaw: UInt8
        if case .uint8(let v) = try smc.read(SMCKey("F\(i)md")) { mdRaw = v } else { mdRaw = 0 }
        return Fan(
            index: i,
            current: cur,
            min: mn,
            max: mx,
            target: tg,
            mode: Fan.Mode(rawValue: mdRaw) ?? .auto
        )
    }

    public func readAllFans() throws -> [Fan] {
        let n = try fanCount()
        return try (0..<n).map { try readFan($0) }
    }

    /// Sets a fan to manual mode at the given target RPM. Clamped to `[Mn, Mx]`.
    public func setManual(_ i: Int, rpm: Double) throws {
        let mn = try smc.read(SMCKey("F\(i)Mn")).asDouble ?? 0
        let mx = try smc.read(SMCKey("F\(i)Mx")).asDouble ?? 6500
        let clamped = Float(Swift.max(mn, Swift.min(mx, rpm)))
        try smc.writeUInt8(SMCKey("F\(i)md"), 1)
        try smc.writeFloat(SMCKey("F\(i)Tg"), clamped)
    }

    /// Hands control back to macOS thermal management.
    public func setAuto(_ i: Int) throws {
        try smc.writeUInt8(SMCKey("F\(i)md"), 0)
    }

    public func setAllAuto() throws {
        let n = (try? fanCount()) ?? 0
        for i in 0..<n { try? setAuto(i) }
    }

    // MARK: - Temperature discovery

    /// Walks the entire SMC keystore once and returns every key that looks
    /// like a temperature reading: starts with 'T', is `flt`/4 bytes, and
    /// produces a sane Celsius value. Sorted hottest first. Cached lazily.
    private var cachedTempKeys: [SMCKey]? = nil
    public func discoverTemperatures() -> [Temperature] {
        let keys: [SMCKey]
        if let cached = cachedTempKeys {
            keys = cached
        } else {
            var found: [SMCKey] = []
            let total = (try? smc.totalKeyCount()) ?? 0
            for i in 0..<total {
                guard let key = try? smc.keyAt(index: i) else { continue }
                let s = key.description
                guard s.hasPrefix("T") else { continue }
                guard let info = try? smc.keyInfo(key),
                      info.dataType == .flt, info.dataSize == 4 else { continue }
                found.append(key)
            }
            cachedTempKeys = found
            keys = found
        }
        var temps: [Temperature] = []
        for key in keys {
            guard let v = try? smc.read(key),
                  let c = v.asDouble,
                  c > -50, c < 150 else { continue }
            temps.append(Temperature(key: key, celsius: c))
        }
        return temps.sorted { $0.celsius > $1.celsius }
    }
}
