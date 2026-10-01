import Foundation

extension BannerStore {
    /// A banner store over the vault of `backend`; course folders come from its course model.
    init(backend: VaultBackend) {
        self.init(store: backend.store, courseFolder: { course in
            guard let entry = await backend.model.entry(course) else { throw MarginError.notFound("No course \(course)") }
            return try VaultPath(components: [entry.semesterFolder, entry.folder])
        })
    }
}

extension VaultBackend {
    func banner(course: CourseID) async throws -> Data? {
        return try await BannerStore(backend: self).read(course: course)?.data
    }

    func setBanner(_ image: Data?, course: CourseID, actor: Actor, baseVersion: String?, dryRun: Bool,
                   idempotencyKey: String?) async throws -> ChangeSet {
        if !dryRun, let cached = idempotency.lookup(actor: actor, key: idempotencyKey) { return cached }
        _ = try writableEntry(course)
        let banners = BannerStore(backend: self)
        let old = try await banners.read(course: course)
        if let baseVersion, old?.version != baseVersion {
            throw MarginError.conflict("The banner of \(course) changed since version \(baseVersion)")
        }
        var entries: [ChangeSet.Entry] = []
        if let image {
            let format = try BannerStore.validate(image)
            let path = try await banners.plannedPath(course: course, format: format)
            let after = ContentHash(of: image).hex
            if old?.path == path, old?.version == after { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
            entries.append(.init(path: path, kind: old?.path == path ? .modified : .created,
                                 beforeHash: old?.path == path ? old?.version : nil, afterHash: after))
            if let old, old.path != path { entries.append(.init(path: old.path, kind: .deleted, beforeHash: old.version)) }
            if !dryRun { try await banners.save(image, course: course) }
        } else {
            guard let old else { return finish(actor: actor, entries: [], dryRun: dryRun, key: idempotencyKey) }
            entries = [.init(path: old.path, kind: .deleted, beforeHash: old.version)]
            if !dryRun { try await banners.remove(course: course) }
        }
        return finish(actor: actor, entries: entries, dryRun: dryRun, key: idempotencyKey)
    }
}
