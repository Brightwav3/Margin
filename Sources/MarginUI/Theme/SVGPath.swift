import CoreGraphics
import Foundation
import SwiftUI

/// Minimal SVG geometry → `Path` for the bundled Lucide set (24×24 viewBox).
///
/// Supports the elements Lucide uses (`path`, `circle`, `ellipse`, `rect`, `line`, `polyline`,
/// `polygon`) and every path command, including arcs and compact number/flag syntax
/// (`a10 10 0 0010-10`, `.5.5`, `1e-3`).
enum SVGPath {
    /// Parses a path `d` attribute. Malformed input stops at the first bad token and keeps
    /// what was drawn so far (an icon never crashes the UI).
    static func parse(_ d: String) -> Path {
        var scanner = Scanner(Array(d.utf8))
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }
            if Scanner.isCommand(next) {
                command = next
                scanner.advance()
            } else if command == 0 {
                break
            }
            let relative = command >= UInt8(ascii: "a")
            let upper = relative ? command - 32 : command
            let origin = relative ? current : .zero

            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }

            var cubic: CGPoint?
            var quad: CGPoint?
            switch upper {
            case UInt8(ascii: "M"):
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                // Further pairs after a moveto are implicit linetos.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"):
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "H"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case UInt8(ascii: "V"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case UInt8(ascii: "C"):
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                cubic = c2
                current = p
            case UInt8(ascii: "S"):
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastCubicControl.map { reflect($0, around: current) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                cubic = c2
                current = p
            case UInt8(ascii: "Q"):
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                quad = c
                current = p
            case UInt8(ascii: "T"):
                guard let p = point() else { return path }
                let c = lastQuadControl.map { reflect($0, around: current) } ?? current
                path.addQuadCurve(to: p, control: c)
                quad = c
                current = p
            case UInt8(ascii: "A"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = point()
                else { return path }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rotation,
                       largeArc: large, sweep: sweep)
                current = p
            case UInt8(ascii: "Z"):
                path.closeSubpath()
                current = subpathStart
                command = 0
            default:
                return path
            }
            lastCubicControl = cubic
            lastQuadControl = quad
        }
        return path
    }

    /// Parses `points` of a polyline/polygon.
    static func points(_ list: String) -> [CGPoint] {
        var scanner = Scanner(Array(list.utf8))
        var result: [CGPoint] = []
        while let x = scanner.number(), let y = scanner.number() {
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    private static func reflect(_ p: CGPoint, around c: CGPoint) -> CGPoint {
        CGPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y)
    }

    /// Endpoint → centre parameterisation (SVG 1.1 §F.6.5), drawn as a transformed unit arc.
    static func addArc(
        to path: inout Path, from p1: CGPoint, to p2: CGPoint,
        rx: CGFloat, ry: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        if p1 == p2 { return }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 {
            path.addLine(to: p2)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (largeArc != sweep ? 1 : -1) * (max(0, num / den)).squareRoot()
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = atan2(uy, ux)
        var delta = atan2(vy, vx) - theta1
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: phi)
            .scaledBy(x: rx, y: ry)
        path.addRelativeArc(
            center: .zero, radius: 1,
            startAngle: .radians(theta1), delta: .radians(delta),
            transform: transform
        )
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func advance() { index += 1 }

        static func isCommand(_ b: UInt8) -> Bool {
            switch b {
            case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
                 UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
                 UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
                 UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
                 UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
                true
            default:
                false
            }
        }

        mutating func skipSeparators() {
            while let b = peek(), b == UInt8(ascii: " ") || b == UInt8(ascii: ",") || b == 0x0A
                || b == 0x0D || b == 0x09 {
                advance()
            }
        }

        /// Arc flags are a single `0`/`1` and may touch the next number (`0010-10`).
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let b = peek(), b == UInt8(ascii: "0") || b == UInt8(ascii: "1") else { return nil }
            advance()
            return b == UInt8(ascii: "1")
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if let b = peek(), b == UInt8(ascii: "-") || b == UInt8(ascii: "+") { advance() }
            var sawDigit = false, sawDot = false
            while let b = peek() {
                if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
                    sawDigit = true
                } else if b == UInt8(ascii: "."), !sawDot {
                    sawDot = true
                } else {
                    break
                }
                advance()
            }
            if sawDigit, let b = peek(), b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
                let mark = index
                advance()
                if let s = peek(), s == UInt8(ascii: "-") || s == UInt8(ascii: "+") { advance() }
                var expDigits = false
                while let d = peek(), d >= UInt8(ascii: "0") && d <= UInt8(ascii: "9") {
                    expDigits = true
                    advance()
                }
                if !expDigits { index = mark }
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return String(decoding: bytes[start..<index], as: UTF8.self).withCString { CGFloat(strtod($0, nil)) }
        }
    }
}
