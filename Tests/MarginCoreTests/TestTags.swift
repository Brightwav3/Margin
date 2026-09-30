import Testing

extension Tag {
    /// Pomalé testy (výkonové rozpočty, robustnost, souběh, injekce chyb, fuzz). Tag slouží jako
    /// dokumentace a pro Xcode; `swift test` z příkazové řádky podle tagů filtrovat neumí, proto
    /// `scripts/test.sh` používá seznam v `scripts/test-tiers.txt`. Obě místa udržuj shodná.
    @Tag static var slow: Self
}
