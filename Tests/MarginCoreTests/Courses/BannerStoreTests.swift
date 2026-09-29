import Foundation
import Testing
@testable import MarginCore

/// M3-05.B: the banner image lives in `<course>/_files/banner.<ext>`, survives a restart and is size limited.
@Suite struct BannerStoreTests {
    static let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]

    /// A "image" of `count` bytes that starts with `header` (only the signature is checked).
    static func image(_ header: [UInt8] = pngHeader, count: Int = 64, fill: UInt8 = 7) -> Data {
        Data(header + [UInt8](repeating: fill, count: max(0, count - header.count)))
    }

    /// A tiny real PNG (1x1).
    static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    struct Setup {
        let dir: TempDir
        let store: VaultStore
        let banners: BannerStore
    }

    static func folders(_ store: VaultStore) -> BannerStore {
        BannerStore(store: store, courseFolder: { course in
            guard course == "bio" else { throw MarginError.notFound("No course \(course)") }
            return try VaultPath("Fall 2026/Cell Biology")
        })
    }

    private func setup() async throws -> Setup {
        let dir = TempDir()
        let store = try await VaultStore.open(root: dir.url, clock: FixedClock())
        return Setup(dir: dir, store: store, banners: Self.folders(store))
    }

    @Test func roundTripStoresTheFileInTheCourseFilesFolder() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        #expect(try await s.banners.read(course: "bio") == nil)

        let saved = try await s.banners.save(Self.tinyPNG, course: "bio")
        #expect(saved.path == "Fall 2026/Cell Biology/_files/banner.png" && saved.format == .png)
        #expect(saved.data == Self.tinyPNG)
        // A plain file on disk, readable by any program.
        let onDisk = try Data(contentsOf: s.dir.url.appendingPathComponent(saved.path))
        #expect(onDisk == Self.tinyPNG)

        let read = try #require(try await s.banners.read(course: "bio"))
        #expect(read == saved)
        #expect(read.version == ContentHash(of: Self.tinyPNG).hex)
    }

    @Test func bannerSurvivesARestart() async throws {
        let dir = TempDir()
        let data = Self.image(Self.jpegHeader, count: 4096, fill: 42)
        do {
            let store = try await VaultStore.open(root: dir.url, clock: FixedClock())
            try await Self.folders(store).save(data, course: "bio")
        }   // the store and everything it held in memory are gone
        let reopened = try await VaultStore.open(root: dir.url, clock: FixedClock())
        let banner = try #require(try await Self.folders(reopened).read(course: "bio"))
        #expect(banner.data == data && banner.format == .jpg)
        #expect(banner.path == "Fall 2026/Cell Biology/_files/banner.jpg")
    }

    @Test func imagesUpToTheLimitAreAcceptedAndLargerOnesRejected() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        let atLimit = Self.image(count: BannerStore.maxBytes)
        try await s.banners.save(atLimit, course: "bio")
        #expect(try await s.banners.read(course: "bio")?.data.count == BannerStore.maxBytes)

        let tooBig = Self.image(count: BannerStore.maxBytes + 1, fill: 9)
        do { try await s.banners.save(tooBig, course: "bio"); Issue.record("accepted") }
        catch let e as MarginError { #expect(e.code == "invalid") }
        // The rejected save changed nothing.
        #expect(try await s.banners.read(course: "bio")?.data == atLimit)
    }

    @Test func rejectsEmptyAndUnknownFormatsWithoutWriting() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        for bad in [Data(), Data("not an image".utf8), Self.image([0x25, 0x50, 0x44, 0x46]) /* %PDF */, Data(Self.pngHeader.prefix(4))] {
            do { try await s.banners.save(bad, course: "bio"); Issue.record("accepted \(bad.count) bytes") }
            catch let e as MarginError { #expect(e.code == "invalid") }
        }
        #expect(try await s.banners.read(course: "bio") == nil)
        #expect(!(await s.store.exists(try VaultPath("Fall 2026/Cell Biology/_files"))))
    }

    @Test func detectsAllAcceptedFormats() {
        #expect(BannerFormat.detect(Self.image(Self.pngHeader)) == .png)
        #expect(BannerFormat.detect(Self.image(Self.jpegHeader)) == .jpg)
        #expect(BannerFormat.detect(Data("GIF89a".utf8) + Data(count: 10)) == .gif)
        #expect(BannerFormat.detect(Data("GIF87a".utf8) + Data(count: 10)) == .gif)
        #expect(BannerFormat.detect(Data("RIFF".utf8) + Data([1, 0, 0, 0]) + Data("WEBP".utf8) + Data(count: 4)) == .webp)
        #expect(BannerFormat.detect(Data("RIFF".utf8) + Data([1, 0, 0, 0]) + Data("WAVE".utf8) + Data(count: 4)) == nil)
        #expect(BannerFormat.detect(Data()) == nil)
    }

    @Test func aBannerOfAnotherFormatReplacesTheOldOneAndTrashesIt() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        let png = try await s.banners.save(Self.tinyPNG, course: "bio")
        let jpg = try await s.banners.save(Self.image(Self.jpegHeader), course: "bio")
        #expect(jpg.path.hasSuffix("banner.jpg"))
        #expect(!(await s.store.exists(try VaultPath(png.path))))
        #expect(try await s.banners.read(course: "bio")?.path == jpg.path)
        // Saving the same format again overwrites in place.
        let again = try await s.banners.save(Self.image(Self.jpegHeader, fill: 1), course: "bio")
        #expect(again.path == jpg.path && again.version != jpg.version)
    }

    @Test func staleBaseVersionIsAConflict() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        let first = try await s.banners.save(Self.tinyPNG, course: "bio")
        let second = try await s.banners.save(Self.image(fill: 3), course: "bio", baseVersion: first.version)
        #expect(second.version != first.version)
        do { try await s.banners.save(Self.image(fill: 4), course: "bio", baseVersion: first.version); Issue.record("accepted") }
        catch let e as MarginError { #expect(e.code == "conflict") }
        #expect(try await s.banners.read(course: "bio")?.version == second.version)
        // A base version for a banner that does not exist is a conflict too.
        do { try await s.banners.remove(course: "bio"); try await s.banners.save(Self.tinyPNG, course: "bio", baseVersion: "abc"); Issue.record("accepted") }
        catch let e as MarginError { #expect(e.code == "conflict") }
    }

    @Test func unknownCourseIsNotFound() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        for op in [{ try await s.banners.save(Self.tinyPNG, course: "nope") }, { try await s.banners.read(course: "nope") == nil },
                   { try await s.banners.remove(course: "nope") }] as [() async throws -> Any] {
            do { _ = try await op(); Issue.record("no error") } catch let e as MarginError { #expect(e.code == "notFound") }
        }
    }

    @Test func removeMovesTheBannerToTheTrash() async throws {
        let s = try await setup(); defer { withExtendedLifetime(s) {} }
        #expect(try await s.banners.remove(course: "bio") == false)
        try await s.banners.save(Self.tinyPNG, course: "bio")
        #expect(try await s.banners.remove(course: "bio") == true)
        #expect(try await s.banners.read(course: "bio") == nil)
    }

    @Test func worksOnTheSampleVaultThroughTheBackend() async throws {
        let dir = TempDir()
        let store = try await VaultStore.open(root: dir.url, clock: FixedClock())
        try await SampleVaultGenerator.generate(into: store, from: Fixtures.week5)
        let backend = try await VaultBackend.open(at: dir.url, clock: FixedClock())
        let banners = BannerStore(backend: backend)
        let saved = try await banners.save(Self.tinyPNG, course: "math")
        #expect(saved.path == "Fall 2026/Linear Algebra/_files/banner.png")
        #expect(try await banners.read(course: "math")?.data == Self.tinyPNG)
        do { _ = try await banners.read(course: "nope") } catch let e as MarginError { #expect(e.code == "notFound") }
        await backend.shutdown()
        // A new backend on the same folder (a restart) still finds it.
        let again = try await VaultBackend.open(at: dir.url, clock: FixedClock())
        #expect(try await BannerStore(backend: again).read(course: "math")?.data == Self.tinyPNG)
        // The banner is not a note and does not disturb the note list of the course.
        #expect(try await again.notes(course: "math").allSatisfy { !$0.title.lowercased().contains("banner") })
        await again.shutdown()
    }
}
