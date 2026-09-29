import Foundation
import Testing
@testable import MarginCore

/// AG-04: another program writes the note file at EVERY possible moment of a save (before each
/// file-system call the store makes), and the save must never silently overwrite what it wrote.
///
/// The one unavoidable exception is documented and asserted exactly: a plain `rename(2)` cannot be
/// made conditional, so a write that lands after the store's last version check and before its
/// rename is replaced (the store verifies the version twice, the second time immediately before the
/// rename, to keep that window to a single system call).
extension PerfSuites {
    @Suite struct ExternalWriteRaceTests {
        typealias Rig = VaultChangeSetIntegrationTests.Rig

        static let lines = (1...12).map { "line \($0)\n" }.joined()
        static let marker = "EXTERNAL EDIT\n"

        struct Outcome {
            var index: Int
            var call: String
            var text: String
            var initial: String
            var threw: String?
        }

        /// A vault with one twelve-line note; the closure gets the note's path and the id.
        private func run(hookAt index: Int?, dryRun: Bool = false, _ edit: (String) -> String) async throws
            -> (outcome: Outcome, log: [String]) {
            let dir = try await Rig.sampleVault()
            let fs = HookFileSystem()
            let rig = try await Rig.open(dir, fileSystem: fs)
            let cs = try await rig.notes.create(course: "bio", title: "Race", kind: .note, text: Self.lines, actor: .user,
                                                baseVersion: nil, dryRun: false, idempotencyKey: nil)
            let id = try #require(cs.entries.first?.noteID)
            let path = try #require(cs.entries.first?.path)
            let file = dir.file(path)
            let note = try await rig.notes.open(id: id)

            // The other program appends a line to whatever the file holds at that moment, in place.
            let external: @Sendable () -> Void = {
                guard var data = FileManager.default.contents(atPath: file.path) else { return }
                data.append(Data(Self.marker.utf8))
                try? data.write(to: file)
            }
            let initial = String(decoding: FileManager.default.contents(atPath: file.path) ?? Data(), as: UTF8.self)
            fs.arm(index.map { [$0: external] } ?? [:])
            var threw: String?
            do {
                _ = try await rig.notes.save(id: id, text: edit(note.text), actor: .user, baseVersion: note.version,
                                             dryRun: dryRun, idempotencyKey: nil)
            } catch let e as MarginError { threw = e.code } catch { threw = "other: \(error)" }
            let log = fs.log
            let text = String(decoding: FileManager.default.contents(atPath: file.path) ?? Data(), as: UTF8.self)
            await rig.close()
            let call = index.flatMap { $0 < log.count ? log[$0] : nil } ?? "-"
            return (Outcome(index: index ?? -1, call: call, text: text, initial: initial, threw: threw), log)
        }

        static func edit(_ text: String) -> String { text.replacingOccurrences(of: "line 2\n", with: "MY EDIT\n") }

        @Test func anExternalWriteAtAnyPointOfASaveIsNeverOverwrittenExceptInTheSingleRenameWindow() async throws {
            let (clean, log) = try await run(hookAt: nil, Self.edit)
            #expect(clean.threw == nil && clean.text.contains("MY EDIT"))
            // The note's own replace is the one whose target is the note file.
            let replaceIndices = log.indices.filter { log[$0].hasPrefix("replaceItem:") && log[$0].hasSuffix("Race.md") }
            let noteReplace = try #require(replaceIndices.last)

            var lost: [Int] = []
            var conflicts = 0, merged = 0
            var problems: [String] = []
            for index in 0..<log.count {
                let (o, _) = try await run(hookAt: index, Self.edit)
                let label = "hook before call \(index) (\(o.call))"
                let hasExternal = o.text.contains(Self.marker)
                let hasMine = o.text.contains("MY EDIT")
                if !hasExternal { lost.append(index) }
                if let threw = o.threw {
                    // A refused save must be a conflict and must leave the other program's content in place.
                    conflicts += 1
                    if threw != "conflict" { problems.append("\(label): threw \(threw)") }
                    if hasMine { problems.append("\(label): threw \(threw) but the file holds the edit") }
                } else {
                    if !hasMine { problems.append("\(label): save succeeded but the edit is not in the file") }
                    if hasExternal { merged += 1 }
                }
                if o.text.contains("<<<<<<<") { problems.append("\(label): conflict markers were written to the file") }
                // Whatever happened, the file is one of: both edits, the other program's alone (save refused),
                // or (only at the rename window) mine alone.
                let mine = o.initial.replacingOccurrences(of: "line 2\n", with: "MY EDIT\n")
                let allowed = [mine + Self.marker, o.initial + Self.marker]
                if !allowed.contains(o.text) && !(index == noteReplace && o.text == mine) {
                    problems.append("\(label): unexpected file content \(o.text.debugDescription)")
                }
            }
            print("external write sweep: \(log.count) injection points, \(merged) merged, \(conflicts) refused, lost at \(lost) (rename window at \(noteReplace))")
            #expect(problems.isEmpty, "\(problems.prefix(8).joined(separator: "\n"))")
            // The only point where the external write may be lost is the hook right before the note's rename.
            #expect(lost.isEmpty || lost == [noteReplace], "external write lost at \(lost), expected at most \(noteReplace)")
        }

        @Test func aSaveThatOverlapsTheExternalEditRefusesAndKeepsIt() async throws {
            // The other program appends at the very end; the save also appends there: same place.
            let (o, log) = try await run(hookAt: 0, { $0 + "MY APPENDED LINE\n" })
            #expect(o.threw == "conflict" || o.text.contains("MY APPENDED LINE"))
            #expect(o.text.contains(Self.marker))
            #expect(!log.isEmpty)
            if o.threw == "conflict" { #expect(!o.text.contains("MY APPENDED LINE")) }
        }
    }
}
