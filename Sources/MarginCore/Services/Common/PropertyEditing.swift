/// Frontmatter edits shared by the fixture and the vault property services. Both work on the whole
/// file content (frontmatter + body) and get the new content back, or `nil` when nothing changes.
enum PropertyEditing {
    /// Keys the app owns.
    static let protectedKeys: Set<String> = ["id"]

    /// Built-in types plus one inferred type per key found in `notes` (first note wins).
    static func registry(inferredFrom notes: [[String: FrontmatterValue]]) -> PropertyRegistry {
        var registry = PropertyRegistry.builtIn
        for properties in notes {
            for key in properties.keys.sorted() where registry.type(for: key) == nil {
                guard let value = properties[key] else { continue }
                try? registry.register(key: key, type: PropertyType.infer(from: value))
            }
        }
        return registry
    }

    static func set(key: String, value: FrontmatterValue, in content: String,
                    registry: PropertyRegistry) throws -> String? {
        try checkKey(key)
        let canonical: FrontmatterValue
        do { canonical = try registry.validate(key: key, value: value) } catch { throw error.marginError }
        var (fm, body) = Frontmatter.parse(content)
        if fm?.value(for: key) == canonical { return nil }
        var block = fm ?? Frontmatter()
        block.set(key, canonical)
        fm = block
        return block.render() + body
    }

    static func remove(key: String, in content: String) throws -> String? {
        try checkKey(key)
        var (fm, body) = Frontmatter.parse(content)
        guard var block = fm, block.remove(key) else { return nil }
        fm = block
        return block.render() + body
    }

    private static func checkKey(_ key: String) throws {
        do { try PropertyRegistry.validateKey(key) } catch { throw error.marginError }
        if protectedKeys.contains(key.lowercased()) {
            throw MarginError.invalid("The property \(key) is managed by Margin and cannot be edited")
        }
    }
}

private extension Error {
    var marginError: MarginError {
        (self as? PropertyValidationError)?.marginError ?? .invalid("\(self)")
    }
}
