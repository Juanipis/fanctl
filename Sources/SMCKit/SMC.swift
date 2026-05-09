import Foundation
import IOKit

/// Thin wrapper around the AppleSMC IOKit user client.
///
/// Communicates with the kernel by packing an `SMCKeyData_t` (80 bytes,
/// see layout below) and calling `IOConnectCallStructMethod` against the
/// `kSMCHandleYPCEvent` (2) selector. The actual operation is encoded in
/// the `data8` byte: 5 = read, 6 = write, 9 = get-key-info.
///
/// Reads work as a normal user. Writes (data8 = 6) require root and are
/// only used by the privileged helper.
public final class SMC: @unchecked Sendable {

    // MARK: - Constants matching the kernel-side struct layout

    /// Total size of `SMCKeyData_t`. The kernel rejects calls with a different size.
    @usableFromInline static let kKeyDataSize = 80

    /// `IOConnectCallStructMethod` selector. Modern AppleSMC only exports this one.
    @usableFromInline static let kHandleYPCEvent: UInt32 = 2

    /// Operation tags placed in `data8` of the input struct.
    private enum Op: UInt8 {
        case read         = 5
        case write        = 6
        case getKeyByIndex = 8
        case getKeyInfo   = 9
    }

    // Field offsets inside the 80-byte SMCKeyData_t. Derived from the C
    // struct with default alignment; verified by `SMCLayoutTests`.
    private enum Offset {
        static let key            = 0   // UInt32 — FourCC packed as host-order int
        // vers: 4..7 (4 bytes), padding to 8
        // pLimitData: 8..23 (16 bytes)
        // padding 24..27
        static let keyInfoSize    = 28  // UInt32
        static let keyInfoType    = 32  // UInt32
        static let keyInfoAttrs   = 36  // UInt8 (+3 pad)
        static let result         = 40  // UInt8
        static let status         = 41  // UInt8
        static let data8          = 42  // UInt8 (operation tag)
        static let data32         = 44  // UInt32 (used by getKeyByIndex)
        static let bytes          = 48  // 32 bytes payload
    }

    // MARK: - Connection

    private var connection: io_connect_t = 0
    public private(set) var matchedClassName: String = ""
    public var debug: Bool = false

    public init() throws {
        // On Apple Silicon the actual class is `AppleSMCKeysEndpoint` with
        // user-client `AppleSMCClient`. On Intel it's `AppleSMC`. Try the
        // Apple Silicon name first, fall back to the legacy name.
        let candidates = ["AppleSMCKeysEndpoint", "AppleSMC"]
        var openedConn: io_connect_t = 0
        var openedName = ""
        var lastKr: kern_return_t = 0
        for name in candidates {
            let service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(name)
            )
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }
            var conn: io_connect_t = 0
            let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
            if kr == kIOReturnSuccess {
                openedConn = conn
                openedName = name
                break
            }
            lastKr = kr
        }
        guard openedConn != 0 else {
            if lastKr != 0 { throw SMCError.openFailed(lastKr) }
            throw SMCError.driverNotFound
        }
        self.connection = openedConn
        self.matchedClassName = openedName
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Public API

    /// Returns dataSize / dataType for a key, or throws `keyNotFound`.
    public func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        var input = makeInput(key: key, op: .getKeyInfo)
        var output = [UInt8](repeating: 0, count: Self.kKeyDataSize)
        try call(input: &input, output: &output)
        let size = readUInt32Host(output, at: Offset.keyInfoSize)
        let type = readUInt32Host(output, at: Offset.keyInfoType)
        if size == 0 { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(
            dataSize: size,
            dataType: SMCType(raw: type),
            dataAttributes: output[Offset.keyInfoAttrs]
        )
    }

    /// Reads a key and returns its decoded value. Decodes common types
    /// (flt, ui8/16/32, si8/16, sp78, fpe2, fp1f); falls back to `.raw`.
    public func read(_ key: SMCKey) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = makeInput(key: key, op: .read)
        // The driver expects keyInfo.dataSize / dataType to be filled by us
        // for the read call, mirroring what getKeyInfo returned.
        writeUInt32Host(&input, info.dataSize, at: Offset.keyInfoSize)
        writeUInt32Host(&input, info.dataType.raw, at: Offset.keyInfoType)
        var output = [UInt8](repeating: 0, count: Self.kKeyDataSize)
        try call(input: &input, output: &output)
        let size = Int(info.dataSize)
        guard size > 0, size <= 32 else {
            throw SMCError.unexpectedDataSize(key, info.dataSize)
        }
        let payload = Array(output[Offset.bytes ..< Offset.bytes + size])
        return decode(key: key, type: info.dataType, bytes: payload)
    }

    /// Writes raw bytes to a key. Type and length must match `keyInfo`.
    /// Requires root — typical EUID 0 from the helper.
    public func write(_ key: SMCKey, type: SMCType, bytes: [UInt8]) throws {
        var input = makeInput(key: key, op: .write)
        writeUInt32Host(&input, UInt32(bytes.count), at: Offset.keyInfoSize)
        writeUInt32Host(&input, type.raw, at: Offset.keyInfoType)
        for (i, b) in bytes.enumerated() where i < 32 {
            input[Offset.bytes + i] = b
        }
        var output = [UInt8](repeating: 0, count: Self.kKeyDataSize)
        try call(input: &input, output: &output)
    }

    /// Writes a Float as the SMC `flt ` type (little-endian IEEE 754, 4 bytes).
    /// Used for `F<n>Tg`.
    public func writeFloat(_ key: SMCKey, _ value: Float) throws {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        try write(key, type: .flt, bytes: bytes)
    }

    /// Writes a UInt8 as `ui8 ` (1 byte). Used for `F<n>md` (0 = auto, 1 = forced).
    public func writeUInt8(_ key: SMCKey, _ value: UInt8) throws {
        try write(key, type: .ui8, bytes: [value])
    }

    /// Returns the FourCC key at the given index. Use together with `#KEY`
    /// (the total key count) to walk the entire SMC keystore.
    public func keyAt(index: UInt32) throws -> SMCKey {
        var input = makeInput(key: SMCKey("    "), op: .getKeyByIndex)
        // The kernel takes the index from the data32 field (offset 44) for
        // selector 8 — host-order.
        writeUInt32Host(&input, index, at: 44)
        var output = [UInt8](repeating: 0, count: Self.kKeyDataSize)
        try call(input: &input, output: &output)
        let raw = readUInt32Host(output, at: Offset.key)
        return SMCKey(rawDecode: raw)
    }

    public func totalKeyCount() throws -> UInt32 {
        if case .uint32(let n) = try read(SMCKey("#KEY")) { return n }
        return 0
    }

    // MARK: - Private helpers

    private func makeInput(key: SMCKey, op: Op) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: Self.kKeyDataSize)
        writeUInt32Host(&buf, key.raw, at: Offset.key)
        buf[Offset.data8] = op.rawValue
        return buf
    }

    /// If true, the operation is passed as the `IOConnectCallStructMethod` selector
    /// itself instead of being encoded in `data8`. Used to probe Apple Silicon
    /// where the YPC indirection appears not to apply.
    public var directSelectorMode: Bool = false

    private func call(input: inout [UInt8], output: inout [UInt8]) throws {
        precondition(input.count == Self.kKeyDataSize)
        precondition(output.count == Self.kKeyDataSize)
        var outSize = size_t(Self.kKeyDataSize)
        let selector: UInt32 = directSelectorMode ? UInt32(input[Offset.data8]) : Self.kHandleYPCEvent
        let kr = input.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) -> kern_return_t in
            output.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    selector,
                    inPtr.baseAddress,
                    Self.kKeyDataSize,
                    outPtr.baseAddress,
                    &outSize
                )
            }
        }
        if debug {
            let keyRaw = readUInt32Host(input, at: Offset.key)
            let keyStr = SMCKey(rawDecode: keyRaw)
            FileHandle.standardError.write(Data(
                "smc-debug: key=\(keyStr) op=\(input[Offset.data8]) kr=0x\(String(kr, radix: 16)) result=\(output[Offset.result]) status=\(output[Offset.status]) outSize=\(outSize) keyInfoSize=\(readUInt32Host(output, at: Offset.keyInfoSize)) type=\(SMCType(raw: readUInt32Host(output, at: Offset.keyInfoType)))\n".utf8
            ))
        }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }
    }

    private func decode(key: SMCKey, type: SMCType, bytes: [UInt8]) -> SMCValue {
        switch type {
        case .flt where bytes.count == 4:
            let v: Float = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
            return .float(v)
        case .ui8 where bytes.count == 1:
            return .uint8(bytes[0])
        case .ui16 where bytes.count == 2:
            return .uint16((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case .ui32 where bytes.count == 4:
            let v = (UInt32(bytes[0]) << 24)
                  | (UInt32(bytes[1]) << 16)
                  | (UInt32(bytes[2]) << 8)
                  |  UInt32(bytes[3])
            return .uint32(v)
        case .si8 where bytes.count == 1:
            return .int8(Int8(bitPattern: bytes[0]))
        case .si16 where bytes.count == 2:
            let u = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return .int16(Int16(bitPattern: u))
        default:
            return .raw(type, bytes)
        }
    }

    // The kernel reads `key` and `dataType` as native UInt32 fields. The
    // FourCC "FNum" packs to 0x464E756D as a host-order integer; on little-
    // endian arm64 that lands in memory as bytes [0x6D, 0x75, 0x4E, 0x46].
    // Apparent paradox solved: FourCC strings appear "reversed" in the wire
    // buffer because the kernel does `keyData->key = 'FNum'`, not a per-byte
    // ASCII copy. So we write/read in host (little-endian) order.
    @inline(__always)
    private func writeUInt32Host(_ buf: inout [UInt8], _ value: UInt32, at offset: Int) {
        buf[offset]     = UInt8( value        & 0xFF)
        buf[offset + 1] = UInt8((value >> 8)  & 0xFF)
        buf[offset + 2] = UInt8((value >> 16) & 0xFF)
        buf[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    @inline(__always)
    private func readUInt32Host(_ buf: [UInt8], at offset: Int) -> UInt32 {
        return  UInt32(buf[offset])
             | (UInt32(buf[offset + 1]) << 8)
             | (UInt32(buf[offset + 2]) << 16)
             | (UInt32(buf[offset + 3]) << 24)
    }
}
