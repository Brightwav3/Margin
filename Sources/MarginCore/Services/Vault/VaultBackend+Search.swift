extension VaultBackend {
    /// The live notes with their course ids, for the search engine.
    func searchSources() async -> [SearchSource] {
        await index.allNotes.filter { Self.isNotePath($0.path) }.map { SearchSource(record: $0, courseID: courseID(of: $0)) }
    }
}
