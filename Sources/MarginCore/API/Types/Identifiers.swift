/// Stable identifiers used across the contract. They are plain strings so they survive
/// JSON, the vault and agent tools unchanged.
///
/// - `CourseID`: the folder-derived slug of a course (`bio`, `chem`); unique within a vault.
/// - `NoteID`: stable id of a note (later assigned by the vault; fixtures use `<course>/<slug>`).
/// - `SemesterID`: slug such as `fall-2026`.
public typealias CourseID = String
public typealias NoteID = String
public typealias SemesterID = String
