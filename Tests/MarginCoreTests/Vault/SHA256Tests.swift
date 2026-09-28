import Foundation
import Testing
@testable import MarginCore

@Suite struct SHA256Tests {
    @Test func officialVectors() {
        #expect(SHA256.hexDigest(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256.hexDigest(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256.hexDigest(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(SHA256.hexDigest(of: Data("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu".utf8))
            == "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
    }

    @Test func millionA() {
        let data = Data(repeating: 0x61, count: 1_000_000)
        #expect(SHA256.hexDigest(of: data) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    /// Lengths around the 55/56/64-byte padding boundaries (expected values from GNU sha256sum).
    @Test func paddingBoundaries() {
        let expected: [Int: String] = [
            1: "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
            55: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
            56: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
            63: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
            64: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
            65: "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
            119: "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
            120: "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
            128: "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e",
            1000: "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
        ]
        for (n, hex) in expected {
            #expect(SHA256.hexDigest(of: Data(repeating: 0x61, count: n)) == hex, "length \(n)")
        }
    }

    @Test func unicodeAndSlices() {
        #expect(ContentHash(of: "Příliš žluťoučký kůň").hex == "c138196469ecb343ba5d804e06a0d6e39315cba3ca1c59fd1d2fe643622ed89d")
        // A Data slice has a non-zero startIndex; the digest must only see its bytes.
        let whole = Data("xxabcxx".utf8)
        #expect(SHA256.hexDigest(of: whole.subdata(in: 2..<5)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(ContentHash(of: whole[2..<5]).hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func contentHashParsingAndCoding() throws {
        let h = ContentHash(of: "abc")
        #expect(ContentHash(hex: h.hex.uppercased()) == h)
        #expect(ContentHash(hex: "abc") == nil)
        #expect(ContentHash(hex: String(repeating: "g", count: 64)) == nil)
        let json = try JSONEncoder().encode([h])
        #expect(try JSONDecoder().decode([ContentHash].self, from: json) == [h])
        #expect(throws: (any Error).self) { try JSONDecoder().decode([ContentHash].self, from: Data("[\"zz\"]".utf8)) }
    }
}
