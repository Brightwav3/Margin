import Foundation

/// A validated, normalized path relative to the vault root (spec 05 §1).
///
/// Invariants: at least one component, no `..`, no absolute paths, no NUL or control characters,
/// no empty components. Normalization removes `.` components, repeated and trailing slashes.
/// Unicode is deliberately NOT normalized: the bytes must match what is on disk.
public struct VaultPath: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    /// Path components, each non-empty and free of `/`.
    public let components: [String]

    /// Longest allowed single component in UTF-8 bytes (APFS/ext4 limit).
    public static let maxComponentBytes = 255

    /// Validates and normalizes `string`; throws `MarginError.invalid` when it is not a safe
    /// vault-relative path.
    public init(_ string: String) throws {
        guard !string.isEmpty else { throw MarginError.invalid("Vault path is empty") }
        guard !string.hasPrefix("/") else { throw MarginError.invalid("Vault path must be relative: \(string.debugDescription)") }
        var parts: [String] = []
        for raw in string.split(separator: "/", omittingEmptySubsequences: true) {
            let part = String(raw)
            if part == "." { continue }
            try VaultPath.validate(component: part, in: string)
            parts.append(part)
        }
        guard !parts.isEmpty else { throw MarginError.invalid("Vault path has no components: \(string.debugDescription)") }
        self.components = parts
    }

    /// Builds a path from already-split components (each validated).
    public init(components: [String]) throws {
        guard !components.isEmpty else { throw MarginError.invalid("Vault path has no components") }
        for c in components {
            guard !c.contains("/") else { throw MarginError.invalid("Path component contains '/': \(c.debugDescription)") }
            guard c != "." else { throw MarginError.invalid("Path component '.' is not allowed") }
            try VaultPath.validate(component: c, in: components.joined(separator: "/"))
        }
        self.components = components
    }

    private static func validate(component: String, in whole: String) throws {
        if component == ".." { throw MarginError.invalid("Vault path must not contain '..': \(whole.debugDescription)") }
        // Measured in NFC, the form the vault creates names in: macOS hands names back decomposed
        // (readdir, FSEvents), and "é" in NFD is three bytes instead of two, so a name the vault
        // itself created at the limit would otherwise be rejected and vanish after a restart.
        if component.precomposedStringWithCanonicalMapping.utf8.count > maxComponentBytes {
            throw MarginError.invalid("Path component is longer than \(maxComponentBytes) bytes")
        }
        for scalar in component.unicodeScalars where scalar.value < 0x20 || scalar.value == 0x7f {
            throw MarginError.invalid("Vault path contains a control character: \(whole.debugDescription)")
        }
    }

    /// `/`-joined normalized form.
    public var rawValue: String { components.joined(separator: "/") }
    public var description: String { rawValue }

    /// Last component (file or folder name).
    public var lastComponent: String { components[components.count - 1] }

    /// Lowercased extension without the dot (`"md"`), or `""`.
    public var pathExtension: String {
        let name = lastComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// Parent folder, or `nil` for a top-level entry.
    public var parent: VaultPath? {
        components.count > 1 ? VaultPath(unchecked: Array(components.dropLast())) : nil
    }

    /// This path plus one more component (validated).
    public func appending(_ component: String) throws -> VaultPath {
        try VaultPath(components: components + [component])
    }

    /// This path plus a relative path (validated).
    public func appending(path: String) throws -> VaultPath {
        try VaultPath(rawValue + "/" + path)
    }

    /// `true` when `self` equals `ancestor` or is nested below it.
    public func isInside(_ ancestor: VaultPath) -> Bool {
        components.count >= ancestor.components.count && Array(components.prefix(ancestor.components.count)) == ancestor.components
    }

    /// `true` for paths under the app-owned `.margin/` folder.
    public var isInternal: Bool { components.first == VaultPath.internalFolderName }

    /// `true` when any component starts with a dot (hidden from listings).
    public var isHidden: Bool { components.contains { $0.hasPrefix(".") } }

    /// Name of the app-owned folder at the vault root.
    public static let internalFolderName = ".margin"

    public static func < (lhs: VaultPath, rhs: VaultPath) -> Bool { lhs.rawValue < rhs.rawValue }

    init(unchecked components: [String]) { self.components = components }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        do { try self.init(s) } catch {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid vault path: \(s.debugDescription)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

extension VaultPath {
    /// Characters the spec forbids in file names (`/ : \`); each is replaced by `-`.
    public static let forbiddenFilenameCharacters: Set<Character> = ["/", ":", "\\"]

    /// Derives a file name (without extension) from a note title (spec 05 §1): forbidden
    /// characters are replaced by `-`, control characters dropped, whitespace trimmed, leading dots
    /// removed (a dotfile would be hidden from listings), text normalized to NFC and truncated to
    /// fit the file-system limit together with a 3-byte `.md`. An empty result becomes `Untitled`.
    /// The title itself stays in the note's `# H1`; this only produces the name on disk.
    public static func filename(fromTitle title: String) -> String {
        var mapped = ""
        for ch in title.precomposedStringWithCanonicalMapping {
            if forbiddenFilenameCharacters.contains(ch) {
                mapped.append("-")
            } else if ch.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
                // Newlines and tabs collapse to a space; other control characters are dropped.
                if ch.isNewline || ch == "\t" { mapped.append(" ") }
            } else {
                mapped.append(ch)
            }
        }
        // Drop leading dots and whitespace scalar by scalar ("dot + combining mark" is one
        // Character but still starts with a dot byte, which would hide the file).
        var name = mapped
        while let first = name.unicodeScalars.first, first == "." || CharacterSet.whitespaces.contains(first) {
            name.unicodeScalars.removeFirst()
        }
        name = name.trimmingCharacters(in: .whitespaces)
        let budget = maxComponentBytes - 3
        while name.utf8.count > budget { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }

    /// `<folder>/<derived name>.md` for a note title.
    public static func note(titled title: String, in folder: VaultPath? = nil) throws -> VaultPath {
        let file = filename(fromTitle: title) + ".md"
        if let folder { return try folder.appending(file) }
        return try VaultPath(components: [file])
    }
}
