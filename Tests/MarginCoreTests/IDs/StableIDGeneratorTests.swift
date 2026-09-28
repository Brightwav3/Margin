import Testing
@testable import MarginCore

@Suite struct StableIDGeneratorTests {
    @Test func formatIsPrefixPlusFourBase32Characters() {
        var g = makeGenerator()
        for _ in 0..<200 {
            let n = g.next(.note), t = g.next(.task)
            #expect(n.hasPrefix("n-") && n.count == 6)
            #expect(t.hasPrefix("t-") && t.count == 6)
            #expect(StableIDGenerator.isGenerated(n, kind: .note))
            #expect(StableIDGenerator.isGenerated(t, kind: .task))
            #expect(!StableIDGenerator.isGenerated(n, kind: .task))
        }
    }

    @Test func sameSeedGivesSameSequenceDifferentSeedDoesNot() {
        var a = makeGenerator(7), b = makeGenerator(7), c = makeGenerator(8)
        let sa = (0..<20).map { _ in a.next(.task) }
        let sb = (0..<20).map { _ in b.next(.task) }
        let sc = (0..<20).map { _ in c.next(.task) }
        #expect(sa == sb)
        #expect(sa != sc)
    }

    @Test func idsAreValidObsidianBlockIdsAndUseWholeAlphabet() {
        var g = makeGenerator(3)
        var seen = Set<Character>()
        for _ in 0..<2000 {
            let id = g.next(.task)
            #expect(id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") })
            seen.formUnion(id.dropFirst(2))
        }
        #expect(seen == Set(StableIDGenerator.alphabet))
        #expect(!seen.contains("i") && !seen.contains("l") && !seen.contains("o") && !seen.contains("u"))
    }

    @Test func neverReturnsAnExistingIDAndStaysUniqueWhenAccumulating() {
        var g = makeGenerator(11)
        var used = Set<String>()
        for _ in 0..<5000 {
            let id = g.next(.task, avoiding: used)
            #expect(used.insert(id).inserted)
        }
    }

    @Test func collisionTriggersARetryWithTheSameLength() {
        // The scripted source first yields all zeros ("t-0000"), then a different value.
        var g = StableIDGenerator(source: ScriptedIDSource(values: [0, 0x1234_5678]))
        let id = g.next(.task, avoiding: ["t-0000"])
        #expect(id != "t-0000")
        #expect(id.count == 6)
    }

    @Test func degenerateSourceStillTerminatesAndAvoidsTheSet() {
        var g = StableIDGenerator(source: ConstantIDSource(value: 0))
        var used = Set<String>()
        for _ in 0..<40 {
            let id = g.next(.note, avoiding: used)
            #expect(used.insert(id).inserted)
            #expect(id.hasPrefix("n-"))
        }
    }

    @Test func lengthGrowsWhenShortIDsCollide() {
        // A constant source produces "t-0000"; blocking it forces a longer body.
        var g = StableIDGenerator(source: ConstantIDSource(value: 0))
        let id = g.next(.task, avoiding: ["t-0000"])
        #expect(id == "t-00000")
    }

    @Test func startLengthIsClamped() {
        var short = StableIDGenerator(source: SeededIDSource(seed: 1), length: 1)
        var long = StableIDGenerator(source: SeededIDSource(seed: 1), length: 99)
        #expect(short.next(.note).count == 2 + 4)
        #expect(long.next(.note).count == 2 + 6)
    }

    @Test func recognisesPlaceholderTaskIDs() {
        #expect(StableIDGenerator.isPlaceholderTaskID("fall-2026/bio/Glossary#L12"))
        #expect(StableIDGenerator.isPlaceholderTaskID("n-9c1e#L3"))
        #expect(!StableIDGenerator.isPlaceholderTaskID("t-4f2a"))
        #expect(!StableIDGenerator.isPlaceholderTaskID("note#Lx"))
        #expect(!StableIDGenerator.isPlaceholderTaskID("note#L"))
    }
}
