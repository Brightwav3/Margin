import SwiftUI

/// Margin's own icons of the rail places (user's call): outlined at rest; the selected place is a
/// solid black shape whose inner lines stay grey, so it reads like a filled SF Symbol. Geometry on
/// the 24-unit grid of Lucide (ISC), split into three parts:
/// - `body`: the closed outline that is filled when selected;
/// - `details`: lines inside the body (door, tray lip, calendar header) — grey when selected;
/// - `accents`: lines outside the body (sun rays, calendar rings) — always black.
enum RailGlyph: String, CaseIterable, Sendable {
    case home, inbox, today, upcoming, help

    var body: [String] {
        switch self {
        case .home: ["M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"]
        case .inbox: ["M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"]
        case .today: ["M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0z"]
        case .upcoming: ["M5 4h14a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"]
        case .help: ["M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0z"]
        }
    }

    var details: [String] {
        switch self {
        case .home: ["M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"]
        case .inbox: ["M22 12h-6l-2 3h-4l-2-3H2"]
        case .today: []
        case .upcoming: ["M3 10h18"]
        case .help: ["M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3", "M12 17h.01"]
        }
    }

    var accents: [String] {
        switch self {
        case .today: ["M12 2v2", "M12 20v2", "m4.93 4.93 1.41 1.41", "m17.66 17.66 1.41 1.41", "M2 12h2", "M20 12h2",
                      "m6.34 17.66-1.41 1.41", "m19.07 4.93-1.41 1.41"]
        case .upcoming: ["M8 2v4", "M16 2v4"]
        default: []
        }
    }
}

/// One rail icon, outlined or (selected) filled.
struct RailIcon: View {
    let glyph: RailGlyph
    var filled = false
    var size: CGFloat = 22

    private static let detailGrey = Color(hex: 0x9A9DA6)

    var body: some View {
        let scale = size / 24
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        func path(_ parts: [String]) -> Path {
            var p = Path()
            for d in parts { p.addPath(SVGPath.parse(d)) }
            return p.applying(transform)
        }
        let line = StrokeStyle(lineWidth: (filled ? 2 : 1.5) * scale, lineCap: .round, lineJoin: .round)
        return ZStack {
            if filled {
                path(glyph.body).fill(MarginColor.ink)
                path(glyph.body).stroke(MarginColor.ink, style: line)
                path(glyph.details).stroke(Self.detailGrey, style: line)
            } else {
                path(glyph.body + glyph.details).stroke(MarginColor.ink, style: line)
            }
            path(glyph.accents).stroke(MarginColor.ink, style: line)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
