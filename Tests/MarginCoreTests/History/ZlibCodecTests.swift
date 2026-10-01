#if canImport(Compression)
import Foundation
import Testing
@testable import MarginCore

/// M11-08: snapshots are standard zlib streams on macOS — readable by other tools and by Margin.
@Suite struct ZlibCodecTests {
    private let text = Data(String(repeating: "Fosfolipidová dvojvrstva — membrána. ", count: 20).utf8)

    @Test func roundTripsAndShrinks() throws {
        let codec = ZlibCodec()
        let packed = try codec.encode(text)
        #expect(packed.count < text.count / 4)
        #expect(packed.first == 0x78)   // zlib header (RFC 1950)
        #expect(try codec.decode(packed, size: text.count) == text)
    }

    /// A stream written by Python's `zlib.compress` decodes, so the format is the standard one.
    @Test func readsAStreamFromAnotherZlib() throws {
        let python = try #require(Data(base64Encoded: "eJxzyy9Oy8/JLMhMyS87vFAhpSw/q6youKQsUeFRwxSF3NTcpKLDC/MS9RTcRhWOKhxVCFIIAPeuYCw="))
        #expect(try ZlibCodec().decode(python, size: text.count) == text)
    }

    @Test func damagedStreamsAreRejected() throws {
        var packed = try ZlibCodec().encode(text)
        packed[packed.count - 1] ^= 0xFF
        #expect(throws: MarginError.self) { try ZlibCodec().decode(packed, size: text.count) }
        #expect(throws: MarginError.self) { try ZlibCodec().decode(Data([1, 2, 3]), size: 10) }
    }
}
#endif
