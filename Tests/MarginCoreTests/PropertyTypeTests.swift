import Testing
@testable import MarginCore

@Suite struct PropertyTypeTests {
    func ok(_ t: PropertyType, _ v: FrontmatterValue) throws -> FrontmatterValue { try t.validate(v) }

    @Test func date() throws {
        let d = LocalDate.literal(2026, 10, 2)
        #expect(try ok(.date, .date(d)) == .date(d))
        #expect(try ok(.date, "2026-10-02") == .date(d))
        #expect(try ok(.date, .dateTime(LocalDateTime(date: d, time: .literal(9, 30)))) == .date(d))
        #expect(throws: PropertyValidationError.invalidDate("2026-02-30")) { try PropertyType.date.validate("2026-02-30") }
        #expect(throws: PropertyValidationError.self) { try PropertyType.date.validate(.number(3)) }
    }

    @Test func text() throws {
        #expect(try ok(.text, "hi") == .string("hi"))
        #expect(try ok(.text, .number(201)) == .string("201"))
        #expect(throws: PropertyValidationError.typeMismatch(expected: .text, found: "list")) {
            try PropertyType.text.validate(["a"])
        }
    }

    @Test func tags() throws {
        #expect(try ok(.tags, ["#bio", "bio", " exam ", ""]) == .list(["bio", "exam"]))
        #expect(try ok(.tags, "a, #b c") == .list(["a", "b", "c"]))
        #expect(throws: PropertyValidationError.invalidElement(.tags, "number")) { try PropertyType.tags.validate([.number(1)]) }
        #expect(throws: PropertyValidationError.self) { try PropertyType.tags.validate(.bool(true)) }
    }

    @Test func number() throws {
        #expect(try ok(.number, .number(2.5)) == .number(2.5))
        #expect(try ok(.number, " 42 ") == .number(42))
        #expect(throws: PropertyValidationError.invalidNumber("abc")) { try PropertyType.number.validate("abc") }
        #expect(throws: PropertyValidationError.self) { try PropertyType.number.validate(.number(.infinity)) }
        #expect(throws: PropertyValidationError.self) { try PropertyType.number.validate(.number(.nan)) }
    }

    @Test func checkbox() throws {
        #expect(try ok(.checkbox, .bool(true)) == .bool(true))
        #expect(try ok(.checkbox, "False") == .bool(false))
        #expect(throws: PropertyValidationError.self) { try PropertyType.checkbox.validate("yes") }
        #expect(throws: PropertyValidationError.self) { try PropertyType.checkbox.validate(.number(1)) }
    }

    @Test func list() throws {
        #expect(try ok(.list, ["a", .number(1)]) == ["a", .number(1)])
        #expect(throws: PropertyValidationError.invalidElement(.list, "list")) { try PropertyType.list.validate([["a"]]) }
        #expect(throws: PropertyValidationError.self) { try PropertyType.list.validate("a") }
    }

    @Test func link() throws {
        #expect(try ok(.link, "[[Cell Biology]]") == "[[Cell Biology]]")
        #expect(try ok(.link, "[[Cell Biology|Bio]]") == "[[Cell Biology|Bio]]")
        #expect(try ok(.link, "Cell Biology") == "[[Cell Biology]]")
        #expect(throws: PropertyValidationError.self) { try PropertyType.link.validate("[[]]") }
        #expect(throws: PropertyValidationError.self) { try PropertyType.link.validate("[[a]] b]]") }
        #expect(throws: PropertyValidationError.self) { try PropertyType.link.validate("") }
    }

    @Test func nullIsRejectedEverywhere() {
        for t in PropertyType.allCases {
            #expect(throws: PropertyValidationError.missingValue(t)) { try t.validate(.null) }
        }
    }

    @Test func defaultsValidateAgainstTheirOwnType() throws {
        for t in PropertyType.allCases where t != .date && t != .link {
            #expect(try t.validate(t.defaultValue) == t.defaultValue)
        }
    }

    @Test func inference() {
        #expect(PropertyType.infer(from: .bool(true)) == .checkbox)
        #expect(PropertyType.infer(from: .number(1)) == .number)
        #expect(PropertyType.infer(from: .date(.literal(2026, 1, 1))) == .date)
        #expect(PropertyType.infer(from: ["a", "b"]) == .tags)
        #expect(PropertyType.infer(from: ["a", .number(1)]) == .list)
        #expect(PropertyType.infer(from: "x") == .text)
    }

    @Test func registry() throws {
        var reg = PropertyRegistry.builtIn
        #expect(reg.type(for: "Due") == .date)
        #expect(try reg.validate(key: "due", value: "2026-10-02") == .date(.literal(2026, 10, 2)))
        try reg.register(key: "Pages", type: .number)
        #expect(reg.type(for: "pages") == .number)
        try reg.register(key: "pages", type: .number)
        #expect(throws: PropertyValidationError.conflictingType(key: "pages", registered: .number, requested: .text)) {
            try reg.register(key: "pages", type: .text)
        }
        #expect(try reg.validate(key: "unknown", value: .bool(true)) == .bool(true))
        #expect(throws: PropertyValidationError.self) { try reg.validate(key: "weight", value: "heavy") }
        for bad in ["", " a", "a:b", "#x", "a\nb"] {
            #expect(throws: PropertyValidationError.invalidKey(bad)) { try PropertyRegistry.validateKey(bad) }
        }
        #expect(PropertyValidationError.invalidNumber("x").marginError == .invalid("not a valid number: x"))
    }
}
