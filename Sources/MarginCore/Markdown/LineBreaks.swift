import Foundation

extension StringProtocol {
    /// Whether the text contains a line feed or a carriage return.
    ///
    /// Checked on Unicode scalars, not characters: `"\r\n"` is a single `Character`, so on macOS
    /// `contains("\n")` and `contains("\r")` are both false for CRLF text (on Linux the Foundation
    /// overload happens to find them), and a CRLF would slip through a "one line" check.
    var containsLineBreak: Bool {
        unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
    }
}
