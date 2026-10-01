import Foundation
#if canImport(Compression)
import Compression
#endif

/// How the text of a snapshot is stored. Every snapshot file is
/// `"MHS1"` + codec id (1 byte) + text length in bytes (4 bytes, big endian) + payload, so a
/// snapshot names its own codec and old files stay readable when the default changes.
///
/// Spec 05 §9 asks for zlib. Foundation on Linux has no compression API, so:
/// - `RawCodec` (id 0) stores the UTF-8 text as is; the default wherever `Compression` is missing.
/// - `ZlibCodec` (id 1, macOS only, `#if canImport(Compression)`) stores a standard zlib stream and is
///   the default there. A snapshot is stored raw when compressing does not make it smaller.
/// - Reading a zlib snapshot on a platform without `Compression` throws `.io`.
public protocol SnapshotCodec: Sendable {
    var id: UInt8 { get }
    func encode(_ data: Data) throws -> Data
    /// `size` is the length of the original data.
    func decode(_ data: Data, size: Int) throws -> Data
}

public struct RawCodec: SnapshotCodec {
    public let id: UInt8 = 0
    public init() {}
    public func encode(_ data: Data) throws -> Data { data }
    public func decode(_ data: Data, size: Int) throws -> Data { data }
}

public enum SnapshotFormat {
    static let magic: [UInt8] = Array("MHS1".utf8)
    static let headerSize = 9

    /// The codec new snapshots are written with.
    public static var preferredCodec: any SnapshotCodec {
        #if canImport(Compression)
        ZlibCodec()
        #else
        RawCodec()
        #endif
    }

    static func codec(id: UInt8) -> (any SnapshotCodec)? {
        switch id {
        case 0: return RawCodec()
        #if canImport(Compression)
        case 1: return ZlibCodec()
        #endif
        default: return nil
        }
    }

    public static func encode(_ text: String, codec: any SnapshotCodec = preferredCodec) -> Data {
        let raw = Data(text.utf8)
        var used: any SnapshotCodec = RawCodec()
        var payload = raw
        if codec.id != 0, let packed = try? codec.encode(raw), packed.count < raw.count { used = codec; payload = packed }
        var out = Data(magic)
        out.append(used.id)
        let n = UInt32(truncatingIfNeeded: raw.count)
        out.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
        out.append(payload)
        return out
    }

    /// The text length in bytes from the header, without decoding. `nil` when it is not a snapshot.
    public static func size(of data: Data) -> Int? { header(data)?.size }

    private static func header(_ data: Data) -> (codec: UInt8, size: Int)? {
        let b = [UInt8](data.prefix(headerSize))
        guard b.count == headerSize, Array(b[0..<4]) == magic else { return nil }
        return (b[4], Int(b[5]) << 24 | Int(b[6]) << 16 | Int(b[7]) << 8 | Int(b[8]))
    }

    public static func decode(_ data: Data) throws -> String {
        guard let h = header(data) else { throw MarginError.io("A history snapshot is damaged (no header)") }
        guard let codec = codec(id: h.codec) else {
            throw MarginError.io("This history snapshot uses compression \(h.codec), which this platform cannot read")
        }
        let payload = Data(data.dropFirst(headerSize))
        let raw = try codec.decode(payload, size: h.size)
        guard raw.count == h.size, let text = String(data: raw, encoding: .utf8) else {
            throw MarginError.io("A history snapshot is damaged (wrong length or not UTF-8)")
        }
        return text
    }
}

/// The zlib container (RFC 1950) around a raw deflate stream. Platform independent; `ZlibCodec`
/// supplies the deflate part where `Compression` exists.
enum ZlibFraming {
    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        return b << 16 | a
    }

    /// `78 9C` + deflate stream + Adler-32 of the original data.
    static func wrap(deflated: Data, original: Data) -> Data {
        var out = Data([0x78, 0x9C])
        out.append(deflated)
        let sum = adler32(original)
        out.append(contentsOf: [UInt8(sum >> 24), UInt8((sum >> 16) & 0xFF), UInt8((sum >> 8) & 0xFF), UInt8(sum & 0xFF)])
        return out
    }

    /// The deflate stream and the checksum of the original data.
    static func unwrap(_ data: Data) throws -> (deflated: Data, adler: UInt32) {
        let b = [UInt8](data)
        guard b.count >= 6, b[0] & 0x0F == 8, (Int(b[0]) << 8 | Int(b[1])) % 31 == 0, b[1] & 0x20 == 0 else {
            throw MarginError.io("A history snapshot is damaged (not a zlib stream)")
        }
        let tail = b.suffix(4)
        let sum = tail.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return (Data(b[2..<(b.count - 4)]), sum)
    }
}

#if canImport(Compression)
/// zlib through Apple's `Compression` framework (`COMPRESSION_ZLIB` is a raw deflate stream, which
/// `ZlibFraming` wraps into a standard zlib stream).
/// Verified on macOS against streams from other zlib implementations (`ZlibCodecTests`).
public struct ZlibCodec: SnapshotCodec {
    public let id: UInt8 = 1
    public init() {}

    public func encode(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw MarginError.invalid("Nothing to compress") }
        let capacity = data.count + data.count / 8 + 64
        var out = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            out.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, capacity, src.bindMemory(to: UInt8.self).baseAddress!,
                                          data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw MarginError.io("Compression failed") }
        return ZlibFraming.wrap(deflated: Data(out.prefix(written)), original: data)
    }

    public func decode(_ data: Data, size: Int) throws -> Data {
        let (deflated, adler) = try ZlibFraming.unwrap(data)
        guard size > 0, !deflated.isEmpty else { throw MarginError.io("A history snapshot is damaged (empty)") }
        var out = [UInt8](repeating: 0, count: size)
        let read = deflated.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, size, src.bindMemory(to: UInt8.self).baseAddress!,
                                          deflated.count, nil, COMPRESSION_ZLIB)
            }
        }
        let result = Data(out.prefix(read))
        guard read == size, ZlibFraming.adler32(result) == adler else { throw MarginError.io("A history snapshot is damaged (checksum)") }
        return result
    }
}
#endif
