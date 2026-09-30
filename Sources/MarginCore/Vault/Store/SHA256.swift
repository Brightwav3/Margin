import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Content version of a vault file: lowercase hex SHA-256 of the exact file bytes.
///
/// Used as the `baseVersion` token for optimistic writes (contract rule 0). Computed from the
/// bytes on disk, never from a decoded `String`, so CRLF, BOM and every other byte survives.
public struct ContentHash: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    /// 64 lowercase hexadecimal characters.
    public let hex: String

    /// Hash of `data`.
    public init(of data: Data) {
        self.hex = SHA256.hexDigest(of: data)
    }

    /// Hash of the UTF-8 bytes of `string`.
    public init(of string: String) {
        self.init(of: Data(string.utf8))
    }

    /// Parses a 64-character hex string (case-insensitive); `nil` when malformed.
    public init?(hex: String) {
        let lower = hex.lowercased()
        guard lower.utf8.count == 64, lower.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) })
        else { return nil }
        self.hex = lower
    }

    public var description: String { hex }

    public static func < (lhs: ContentHash, rhs: ContentHash) -> Bool { lhs.hex < rhs.hex }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let h = ContentHash(hex: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a SHA-256 hex digest")
        }
        self = h
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

/// SHA-256 (FIPS 180-4). On Apple platforms through CryptoKit (system framework, hardware-accelerated;
/// the pure-Swift version is ~100x slower in debug builds and dominated the stress tests). CryptoKit is
/// not available on Linux and MarginCore takes no third-party dependencies (D-007), so the portable
/// pure-Swift digest stays here, covered by test vectors and by a comparison with CryptoKit.
public enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// The 32-byte digest of `data`.
    public static func digest(of data: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(CryptoKit.SHA256.hash(data: data))
        #else
        return portableDigest(of: data)
        #endif
    }

    /// The pure-Swift digest, used where CryptoKit is missing (Linux).
    static func portableDigest(of data: Data) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var w = [UInt32](repeating: 0, count: 64)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let full = raw.count / 64
            for block in 0..<full {
                compress(&h, &w, raw.baseAddress!.advanced(by: block * 64).assumingMemoryBound(to: UInt8.self))
            }
            // Final one or two blocks: remaining bytes, 0x80, zero padding, 64-bit big-endian bit length.
            let rest = raw.count - full * 64
            var tail = [UInt8](repeating: 0, count: rest + 1 + 8 + 64)
            if rest > 0, let base = raw.baseAddress {
                for i in 0..<rest { tail[i] = base.load(fromByteOffset: full * 64 + i, as: UInt8.self) }
            }
            tail[rest] = 0x80
            let padded = (rest + 1 + 8 <= 64) ? 64 : 128
            let bitLength = UInt64(raw.count) &* 8
            for i in 0..<8 { tail[padded - 1 - i] = UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i))) }
            tail.withUnsafeBufferPointer { t in
                var offset = 0
                while offset < padded {
                    compress(&h, &w, t.baseAddress!.advanced(by: offset))
                    offset += 64
                }
            }
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8(truncatingIfNeeded: word >> 24))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word))
        }
        return out
    }

    /// Lowercase hex digest of `data`.
    public static func hexDigest(of data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var chars = [UInt8]()
        chars.reserveCapacity(64)
        for byte in digest(of: data) {
            chars.append(digits[Int(byte >> 4)])
            chars.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: chars, as: UTF8.self)
    }

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private static func compress(_ h: inout [UInt32], _ w: inout [UInt32], _ p: UnsafePointer<UInt8>) {
        for i in 0..<16 {
            let j = i * 4
            w[i] = (UInt32(p[j]) << 24) | (UInt32(p[j + 1]) << 16) | (UInt32(p[j + 2]) << 8) | UInt32(p[j + 3])
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }
}
