import Foundation
import Testing
@testable import MarginCore

@Suite struct PropertyEditingTests {
    let registry = PropertyRegistry.builtIn

    @Test func commentsUnknownKeysAndOrderSurviveASet() throws {
        let text = "---\n# my comment\nzeta: 1\nid: n-1   # keep\nalpha:\n  - a\n  - b\ntype: lecture\n---\n\n# Body\n"
        let out = try #require(try PropertyEditing.set(key: "type", value: .string("lab"), in: text, registry: registry))
        #expect(out == text.replacingOccurrences(of: "type: lecture", with: "type: lab"))
    }

    @Test func crlfFilesGetCrlfEntries() throws {
        let text = "---\r\nid: n-1\r\n---\r\nBody\r\n"
        let out = try #require(try PropertyEditing.set(key: "mood", value: .string("calm"), in: text, registry: registry))
        #expect(out == "---\r\nid: n-1\r\nmood: calm\r\n---\r\nBody\r\n")
    }

    @Test func noteWithoutFrontmatterGetsABlock() throws {
        let out = try #require(try PropertyEditing.set(key: "tags", value: .list(["a"]), in: "# Just text\n", registry: registry))
        let (fm, body) = Frontmatter.parse(out)
        #expect(fm?.value(for: "tags") == .list(["a"]))
        #expect(body == "# Just text\n")
        #expect(try PropertyEditing.remove(key: "tags", in: "# Just text\n") == nil)
    }

    @Test func removeKeepsOtherLinesByteForByte() throws {
        let text = "---\nid: n-1\n# note\nmood: calm\nrating: 4\n---\nBody"
        let out = try #require(try PropertyEditing.remove(key: "mood", in: text))
        #expect(out == "---\nid: n-1\n# note\nrating: 4\n---\nBody")
    }

    @Test func registryInfersTypesOfUnknownKeysFirstNoteWins() {
        let r = PropertyEditing.registry(inferredFrom: [["Rating": .number(1), "tags": .string("x")], ["rating": .string("high")]])
        #expect(r.type(for: "rating") == .number)
        #expect(r.type(for: "tags") == .tags)      // built-in wins over inference
    }

    @Test func valuesRoundTripThroughJSON() throws {
        let values: [FrontmatterValue] = [
            .null, .bool(true), .number(2.5), .string("x"), .date(.literal(2026, 10, 1)),
            .dateTime(LocalDateTime(date: .literal(2026, 10, 1), time: .literal(10, 30))),
            .list([.string("a"), .number(1)]), .map([.init("k", .bool(false)), .init("a", .string("z"))]),
        ]
        let property = values.map { NoteProperty(key: "k", type: PropertyType.infer(from: $0), value: $0) }
        let data = try JSONEncoder().encode(property)
        #expect(try JSONDecoder().decode([NoteProperty].self, from: data) == property)
    }
}
