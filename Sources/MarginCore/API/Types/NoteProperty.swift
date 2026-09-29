/// One frontmatter property of a note, in file order.
///
/// `type` is the registered type of the key (`PropertyRegistry`), else the one inferred from the
/// value. Unknown keys are listed too and are never dropped.
public struct NoteProperty: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public var key: String
    public var type: PropertyType
    public var value: FrontmatterValue

    public init(key: String, type: PropertyType, value: FrontmatterValue) {
        self.key = key; self.type = type; self.value = value
    }
}
