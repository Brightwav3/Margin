/// Note properties (the YAML frontmatter, vault spec 05 §2) as typed key/value pairs.
///
/// Reading a note's properties is `NoteAnalysis.properties(id:)`. Writes take the write context of
/// contract rule 0 (`actor`, `baseVersion`, `dryRun`, `idempotencyKey`) and return the `ChangeSet`.
///
/// Implementations: `FixturePropertyService` and `VaultPropertyService`. Rules both obey (checked by
/// `Tests/Conformance/PropertyServiceConformanceTests.swift`):
///
/// - **Lossless:** only the edited entry changes. Order, unknown keys, comments and the body stay
///   byte for byte; a new key is appended after the last entry.
/// - **Types:** `types()` lists the built-in keys (`date`, `due`, `tags`, `class`, `weight`, `type`)
///   plus keys found in notes, typed by inference, keys lower-cased. `set` validates the value against
///   the key's type and stores its canonical form (`#tag` -> `tag`, `Note` -> `[[Note]]`); a value that
///   does not fit throws `MarginError.invalid` and changes nothing.
/// - **No-ops:** setting the value a key already has, or removing an absent key, returns an empty
///   `ChangeSet`.
/// - **Protected:** `id` (the stable note id) can be neither set nor removed (`.invalid`).
/// - **Errors:** unknown note `.notFound`; stale `baseVersion` `.conflict`; a bad key `.invalid`.
/// - A note without frontmatter gets a block when its first property is set.
public protocol PropertyService: Sendable {
    /// Type of every known property key (keys lower-cased).
    func types() async throws -> [String: PropertyType]

    /// Sets a property of a note.
    func set(key: String, value: FrontmatterValue, on note: NoteID, actor: Actor, baseVersion: String?,
             dryRun: Bool, idempotencyKey: String?) async throws -> ChangeSet

    /// Removes a property from a note.
    func remove(key: String, on note: NoteID, actor: Actor, baseVersion: String?, dryRun: Bool,
                idempotencyKey: String?) async throws -> ChangeSet
}
