import Foundation

/// Image formats accepted for a course banner, recognised by their first bytes (the file name and
/// any extension the caller has in mind are not trusted).
public enum BannerFormat: String, Codable, Sendable, Hashable, CaseIterable {
    case png, jpg, gif, webp

    /// Extension of the stored file (`banner.jpg`).
    public var fileExtension: String { rawValue }

    /// The format of `data`, or `nil` when it is none of the accepted ones.
    public static func detect(_ data: Data) -> BannerFormat? {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpg }
        if b.starts(with: Array("GIF87a".utf8)) || b.starts(with: Array("GIF89a".utf8)) { return .gif }
        if b.count == 12, b.starts(with: Array("RIFF".utf8)), b[8...].elementsEqual(Array("WEBP".utf8)) { return .webp }
        return nil
    }
}

/// A stored course banner.
public struct BannerImage: Sendable, Hashable {
    public var data: Data
    public var format: BannerFormat
    /// Vault-relative path of the file (`Fall 2026/Cell Biology/_files/banner.png`).
    public var path: String
    /// Opaque version of the file (changes with its bytes).
    public var version: String
}

/// Saves and reads the banner image of a course (M3-05.B): `<course folder>/_files/banner.<ext>`
/// (vault spec 05 §1).
///
/// - **Writes** go through `VaultStore.writeData`: atomic, never a half-written banner.
/// - **Size:** at most `maxBytes` (5 MB); larger or empty data is `MarginError.invalid`, and so is
///   data that is not a PNG, JPEG, GIF or WebP.
/// - **One banner per course:** saving an image of another format replaces the old file, which goes
///   to the trash (never destroyed). Should a hand-edited vault hold several, `read` prefers
///   png, jpg, webp, gif in that order.
/// - **Errors:** unknown course `.notFound`; stale `baseVersion` `.conflict`, nothing written.
///
/// The services reach it through `CourseCatalog.banner(course:)` and `CourseCatalogWriter.setBanner`.
public struct BannerStore: Sendable {
    /// Largest accepted image, in bytes.
    public static let maxBytes = 5 * 1024 * 1024
    /// Folder inside a course folder that holds attachments.
    public static let filesFolder = "_files"
    /// File name without extension.
    public static let baseName = "banner"

    private let store: VaultStore
    private let courseFolder: @Sendable (CourseID) async throws -> VaultPath

    /// - Parameter courseFolder: the vault-relative folder of a course (`Fall 2026/Cell Biology`);
    ///   throws `MarginError.notFound` for an unknown course.
    public init(store: VaultStore, courseFolder: @escaping @Sendable (CourseID) async throws -> VaultPath) {
        self.store = store; self.courseFolder = courseFolder
    }

    /// Stores `data` as the banner of `course`.
    ///
    /// - Parameter baseVersion: the `version` of the banner the caller replaces; when the stored
    ///   banner differs (or does not exist though a version is given) the call throws `.conflict`.
    ///   `nil` replaces whatever is there.
    /// The format of an acceptable banner, else `.invalid` (empty, over `maxBytes`, not an image).
    public static func validate(_ data: Data) throws -> BannerFormat {
        guard !data.isEmpty else { throw MarginError.invalid("The banner image is empty") }
        guard data.count <= maxBytes else {
            throw MarginError.invalid("The banner image is \(data.count) bytes; the limit is \(maxBytes)")
        }
        guard let format = BannerFormat.detect(data) else {
            throw MarginError.invalid("The banner must be a PNG, JPEG, GIF or WebP image")
        }
        return format
    }

    /// Where `course`'s banner of `format` is stored (vault-relative).
    public func plannedPath(course: CourseID, format: BannerFormat) async throws -> String {
        try path(in: try await courseFolder(course), format: format).rawValue
    }

    @discardableResult
    public func save(_ data: Data, course: CourseID, baseVersion: String? = nil) async throws -> BannerImage {
        let format = try Self.validate(data)
        let folder = try await courseFolder(course)
        let target = try path(in: folder, format: format)
        let existing = try await existingBanners(in: folder)

        if let baseVersion {
            guard let current = existing.first, current.version.hex == baseVersion else {
                throw MarginError.conflict("The banner of \(course) changed since version \(baseVersion)")
            }
        }
        let same = existing.first { $0.path == target }
        let version = try await store.writeData(target, data: data, expectedVersion: same?.version)
        for other in existing where other.path != target { _ = try await store.trash(other.path) }
        return BannerImage(data: data, format: format, path: target.rawValue, version: version.hex)
    }

    /// The banner of `course`, or `nil` when it has none. Unknown course: `.notFound`.
    public func read(course: CourseID) async throws -> BannerImage? {
        let folder = try await courseFolder(course)
        guard let found = try await existingBanners(in: folder).first else { return nil }
        let (data, version) = try await store.readData(found.path)
        return BannerImage(data: data, format: found.format, path: found.path.rawValue, version: version.hex)
    }

    /// Moves the banner to the trash. Returns `false` when there was none.
    @discardableResult
    public func remove(course: CourseID) async throws -> Bool {
        let folder = try await courseFolder(course)
        let existing = try await existingBanners(in: folder)
        for banner in existing { _ = try await store.trash(banner.path) }
        return !existing.isEmpty
    }

    // MARK: Internals

    private struct Found { var path: VaultPath; var format: BannerFormat; var version: ContentHash }

    private func path(in folder: VaultPath, format: BannerFormat) throws -> VaultPath {
        try VaultPath(components: folder.components + [Self.filesFolder, "\(Self.baseName).\(format.fileExtension)"])
    }

    /// The banner files that exist, in preference order png, jpg, webp, gif.
    private func existingBanners(in folder: VaultPath) async throws -> [Found] {
        var result: [Found] = []
        for format in [BannerFormat.png, .jpg, .webp, .gif] {
            let p = try path(in: folder, format: format)
            if let v = try await store.version(of: p) { result.append(Found(path: p, format: format, version: v)) }
        }
        return result
    }
}
