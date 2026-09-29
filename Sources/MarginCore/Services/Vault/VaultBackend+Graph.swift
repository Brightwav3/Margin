extension VaultBackend {
    /// The unplaced graph of the vault: every course, every note and the unresolved link targets.
    func graphSnapshot() async -> GraphSnapshot {
        let model = self.model
        return await GraphBuilder.build(
            index: index, courses: ServiceRules.sortCourses(model.courses),
            isNote: { VaultBackend.isNotePath($0.path) },
            courseOf: { model.courseID(semesterFolder: $0.semesterID, folder: $0.courseID, className: $0.className) })
    }
}
