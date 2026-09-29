extension BannerStore {
    /// A banner store over the vault of `backend`; course folders come from its course model.
    init(backend: VaultBackend) {
        self.init(store: backend.store, courseFolder: { course in
            guard let entry = await backend.model.entry(course) else { throw MarginError.notFound("No course \(course)") }
            return try VaultPath(components: [entry.semesterFolder, entry.folder])
        })
    }
}
