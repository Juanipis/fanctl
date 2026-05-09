import Foundation

/// FourCC-style SMC key, e.g. "F0Ac", "FNum", "TC0P".
public struct SMCKey: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt32

    public init(_ ascii: String) {
        precondition(ascii.utf8.count == 4, "SMC keys are 4 ASCII chars: \(ascii)")
        var v: UInt32 = 0
        for byte in ascii.utf8 { v = (v << 8) | UInt32(byte) }
        self.raw = v
    }

    public init(rawDecode: UInt32) { self.raw = rawDecode }

    public var description: String {
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

/// SMC type tag, also a FourCC: "flt ", "ui8 ", "ui16", "ui32", "fp1f", "fpe2", "sp78", ...
public struct SMCType: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt32

    public init(_ ascii: String) {
        precondition(ascii.utf8.count == 4, "SMC types are 4 ASCII chars: \(ascii)")
        var v: UInt32 = 0
        for byte in ascii.utf8 { v = (v << 8) | UInt32(byte) }
        self.raw = v
    }

    public init(raw: UInt32) { self.raw = raw }

    public var description: String {
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    public static let flt  = SMCType("flt ")
    public static let ui8  = SMCType("ui8 ")
    public static let ui16 = SMCType("ui16")
    public static let ui32 = SMCType("ui32")
    public static let si8  = SMCType("si8 ")
    public static let si16 = SMCType("si16")
    public static let sp78 = SMCType("sp78")
    public static let fp1f = SMCType("fp1f")
    public static let fpe2 = SMCType("fpe2")
}

/// Decoded value of a key. Caller usually knows the expected type.
public enum SMCValue: Sendable, CustomStringConvertible {
    case float(Float)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case int8(Int8)
    case int16(Int16)
    case raw(SMCType, [UInt8])

    public var description: String {
        switch self {
        case .float(let v):  return String(format: "%.2f", v)
        case .uint8(let v):  return String(v)
        case .uint16(let v): return String(v)
        case .uint32(let v): return String(v)
        case .int8(let v):   return String(v)
        case .int16(let v):  return String(v)
        case .raw(let t, let b):
            return "\(t)[\(b.map { String(format: "%02x", $0) }.joined())]"
        }
    }

    /// Best-effort numeric coercion — useful for fan RPM and temperature reads.
    public var asDouble: Double? {
        switch self {
        case .float(let v):  return Double(v)
        case .uint8(let v):  return Double(v)
        case .uint16(let v): return Double(v)
        case .uint32(let v): return Double(v)
        case .int8(let v):   return Double(v)
        case .int16(let v):  return Double(v)
        case .raw(let t, let b):
            // sp78 = signed 16-bit fixed-point with 8 fractional bits (temperatures)
            if t == .sp78, b.count >= 2 {
                let i16 = Int16(bitPattern: (UInt16(b[0]) << 8) | UInt16(b[1]))
                return Double(i16) / 256.0
            }
            // fpe2 = unsigned 16-bit, 14 integer bits, 2 fractional bits
            if t == .fpe2, b.count >= 2 {
                let u16 = (UInt16(b[0]) << 8) | UInt16(b[1])
                return Double(u16) / 4.0
            }
            // fp1f = unsigned 16-bit, 1 integer bit, 15 fractional bits
            if t == .fp1f, b.count >= 2 {
                let u16 = (UInt16(b[0]) << 8) | UInt16(b[1])
                return Double(u16) / 32768.0
            }
            return nil
        }
    }
}

public struct SMCKeyInfo: Sendable {
    public let dataSize: UInt32
    public let dataType: SMCType
    public let dataAttributes: UInt8
}

public enum SMCError: Error, CustomStringConvertible {
    case driverNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyNotFound(SMCKey)
    case unexpectedDataSize(SMCKey, UInt32)
    case decodingFailed(SMCKey, SMCType)

    public var description: String {
        switch self {
        case .driverNotFound:           return "AppleSMC IOService not found"
        case .openFailed(let r):        return "IOServiceOpen failed: kr=0x\(String(r, radix: 16))"
        case .callFailed(let r):        return "IOConnectCallStructMethod failed: kr=0x\(String(r, radix: 16))"
        case .keyNotFound(let k):       return "Key not found: \(k)"
        case .unexpectedDataSize(let k, let s): return "Unexpected dataSize \(s) for key \(k)"
        case .decodingFailed(let k, let t):     return "Could not decode \(k) as \(t)"
        }
    }
}
