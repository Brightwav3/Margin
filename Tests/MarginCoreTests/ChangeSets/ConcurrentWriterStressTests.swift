import Foundation
import Testing
@testable import MarginCore

/// AG-04 acceptance: "two writers x 1000 writes without loss". Every write is a read-modify-write
/// with `baseVersion` through the public `NoteRepository`; a `.conflict` is answered by reading the
/// note again and repeating the edit.
extension HeavySuites {
    @Suite struct ConcurrentWriterStressTests {
        typealias Rig = VaultChangeSetIntegrationTests.Rig

        static let writes = 1_000

        static func agent(_ n: Int) -> Actor { .agent(identity: "writer-\(n)", client: "stress", session: "s-\(n)") }

        static func note(_ rig: Rig, seed: String) async throws -> NoteID {
            let cs = try await rig.notes.create(course: "bio", title: "Stress", kind: .note, text: seed, actor: .user,
                                                baseVersion: nil, dryRun: false, idempotencyKey: nil)
            return try #require(cs.entries.first?.noteID)
        }

        /// Counts of a note's lines.
        static func lineCounts(_ text: String) -> [String: Int] {
            var counts: [String: Int] = [:]
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) { counts[String(line), default: 0] += 1 }
            return counts
        }

        // MARK: Two writers appending to the same place

        @Test func twoWritersAppendingAThousandLinesEachLoseNothing() async throws {
            let dir = try await Rig.sampleVault()
            let rig = try await Rig.open(dir)
            let id = try await Self.note(rig, seed: "# Stress\n")
            let notes = rig.notes
            let n = Self.writes

            let conflicts = try await withThrowingTaskGroup(of: Int.self) { group in
                for w in 0..<2 {
                    group.addTask {
                        var conflicts = 0
                        for i in 0..<n {
                            let line = "writer\(w) line \(i)\n"
                            while true {
                                let current = try await notes.open(id: id)
                                do {
                                    _ = try await notes.save(id: id, text: current.text + line, actor: Self.agent(w),
                                                             baseVersion: current.version, dryRun: false, idempotencyKey: nil)
                                    break
                                } catch let e as MarginError where e.code == "conflict" {
                                    #expect(e.conflictDetail?.currentVersion != nil)
                                    conflicts += 1
                                }
                            }
                        }
                        return conflicts
                    }
                }
                return try await group.reduce(0, +)
            }
            print("stress (same place): 2 x \(n) writes, \(conflicts) conflicts retried")

            let text = try await rig.notes.open(id: id).text
            let counts = Self.lineCounts(text)
            #expect(counts.count == 2 * n + 1)
            for w in 0..<2 {
                var last = -1
                for i in 0..<n {
                    #expect(counts["writer\(w) line \(i)"] == 1, "writer\(w) line \(i) appears \(counts["writer\(w) line \(i)"] ?? 0) times")
                    // Each writer's own lines stay in the order it wrote them.
                    let position = text.range(of: "writer\(w) line \(i)\n")?.lowerBound.utf16Offset(in: text) ?? -1
                    #expect(position > last)
                    last = position
                }
            }
            #expect(text.hasPrefix("# Stress\n"))

            // The journal followed along: only the newest 500 are kept, on disk as in the listing.
            let listed = try await rig.changes.changes(limit: nil)
            #expect(listed.count == 500)
            #expect(dir.journalFiles().filter { $0.hasSuffix(".meta.json") }.count == 500)
            #expect(dir.journalFiles().filter { $0.contains(".op-") }.count == 500)
            // And the newest change can still be undone exactly.
            let before = try await rig.notes.open(id: id)
            _ = try await rig.changes.undo(id: listed[0].id, actor: .user)
            let after = try await rig.notes.open(id: id)
            #expect(before.text.hasPrefix(after.text) && after.text.utf8.count < before.text.utf8.count)
            await rig.close()
        }

        // MARK: Two writers in different places: merged without retries

        @Test func twoWritersEditingDifferentEndsAreMergedAutomatically() async throws {
            let dir = try await Rig.sampleVault()
            let rig = try await Rig.open(dir)
            let filler = (1...30).map { "filler \($0)\n" }.joined()
            let id = try await Self.note(rig, seed: "# Stress\n" + filler)
            let notes = rig.notes
            let n = Self.writes

            let (conflicts, merged) = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                for w in 0..<2 {
                    group.addTask {
                        var conflicts = 0, merged = 0
                        for i in 0..<n {
                            let line = "writer\(w) line \(i)\n"
                            while true {
                                let current = try await notes.open(id: id)
                                // Writer 0 inserts right below the heading, writer 1 appends at the end.
                                let text = w == 0
                                    ? current.text.replacingOccurrences(of: "# Stress\n", with: "# Stress\n" + line)
                                    : current.text + line
                                do {
                                    let cs = try await notes.save(id: id, text: text, actor: Self.agent(w),
                                                                  baseVersion: current.version, dryRun: false, idempotencyKey: nil)
                                    if cs.entries.first?.merged == true { merged += 1 }
                                    break
                                } catch let e as MarginError where e.code == "conflict" {
                                    conflicts += 1
                                }
                            }
                        }
                        return (conflicts, merged)
                    }
                }
                return try await group.reduce((0, 0)) { ($0.0 + $1.0, $0.1 + $1.1) }
            }
            print("stress (different ends): 2 x \(n) writes, \(merged) merged automatically, \(conflicts) conflicts retried")

            let text = try await rig.notes.open(id: id).text
            let counts = Self.lineCounts(text)
            #expect(counts.count == 2 * n + 1 + 30)
            for w in 0..<2 { for i in 0..<n { #expect(counts["writer\(w) line \(i)"] == 1) } }
            #expect(text.contains(filler), "the untouched middle changed")
            // Independent regions never conflict: whenever a save was stale it merged.
            #expect(conflicts == 0, "\(conflicts) conflicts for edits that do not overlap")
            #expect(merged > 0)
            await rig.close()
        }

        // MARK: An external writer racing the store

        /// Another program (think Obsidian) appends lines by reading the file and replacing it. It cannot
        /// lock against the store, so a lost update is possible in the instant between its last check
        /// and its rename (and likewise for the store's). Both sides therefore verify at the end and
        /// re-add what is missing; the test measures how often that was needed.
        @Test func anExternalWriterRacingTheStoreLosesNothingOnceBothSidesReconcile() async throws {
            let dir = try await Rig.sampleVault()
            let rig = try await Rig.open(dir)
            let id = try await Self.note(rig, seed: "# Stress\n")
            let path = try #require(dir.userFiles().keys.first { $0.hasSuffix("/Stress.md") })
            let file = dir.file(path)
            let notes = rig.notes
            let n = Self.writes

            /// One external append: read, append, write a temp file next to it, check the file did not
            /// change, rename. Returns `false` when the file changed under it (nothing was written).
            @Sendable func externalAppend(_ line: String) -> Bool {
                guard let a = FileManager.default.contents(atPath: file.path) else { return false }
                let temp = file.deletingLastPathComponent().appendingPathComponent(".ext-\(UUID().uuidString).tmp")
                do { try (a + Data(line.utf8)).write(to: temp) } catch { return false }
                guard FileManager.default.contents(atPath: file.path) == a else { try? FileManager.default.removeItem(at: temp); return false }
                return rename(temp.path, file.path) == 0
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for i in 0..<n {
                        while true {
                            guard let current = try? await notes.open(id: id) else { continue }
                            do {
                                _ = try await notes.save(id: id, text: current.text + "store line \(i)\n", actor: Self.agent(0),
                                                         baseVersion: current.version, dryRun: false, idempotencyKey: nil)
                                break
                            } catch let e as MarginError where e.code == "conflict" { continue } catch { continue }
                        }
                    }
                }
                group.addTask {
                    for i in 0..<n {
                        while !externalAppend("external line \(i)\n") { await Task.yield() }
                    }
                }
            }

            // Reconcile: whoever finds its lines missing writes them again.
            var repairs = 0
            for round in 1...5 {
                let counts = Self.lineCounts(try await notes.open(id: id).text)
                let missingStore = (0..<n).filter { counts["store line \($0)"] == nil }
                let missingExternal = (0..<n).filter { counts["external line \($0)"] == nil }
                if missingStore.isEmpty && missingExternal.isEmpty { break }
                #expect(round < 5, "still missing lines after reconciling: \(missingStore.count) store, \(missingExternal.count) external")
                repairs += missingStore.count + missingExternal.count
                for i in missingStore {
                    let current = try await notes.open(id: id)
                    _ = try await notes.save(id: id, text: current.text + "store line \(i)\n", actor: Self.agent(0),
                                             baseVersion: current.version, dryRun: false, idempotencyKey: nil)
                }
                for i in missingExternal { while !externalAppend("external line \(i)\n") { await Task.yield() } }
            }
            print("stress (external writer): 2 x \(n) writes, \(repairs) lost updates repaired at the end")

            let text = try await notes.open(id: id).text
            let counts = Self.lineCounts(text)
            #expect(counts.count == 2 * n + 1)
            for i in 0..<n {
                #expect(counts["store line \(i)"] == 1, "store line \(i) x\(counts["store line \(i)"] ?? 0)")
                #expect(counts["external line \(i)"] == 1, "external line \(i) x\(counts["external line \(i)"] ?? 0)")
            }
            // No half-written or merged lines, no conflict markers.
            #expect(!text.contains("<<<<<<<") && !text.contains(">>>>>>>"))
            #expect(repairs <= n / 10, "\(repairs) of \(2 * n) updates were lost to the unavoidable race window")
            await rig.close()
        }
    }
}
