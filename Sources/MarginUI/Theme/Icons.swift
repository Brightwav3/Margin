import Foundation
import MarginCore
import Synchronization
import SwiftUI

/// Lucide icons (ISC, pinned in `scripts/gen-icons.py`), the whole set bundled as
/// `Resources/lucide-icons.json` and turned into paths on first use (D-006, D-020).
public final class LucideIcons: Sendable {
    public static let shared = LucideIcons()

    struct Glyph: Sendable {
        var stroke = Path()
        var fill = Path()
    }

    public let version: String
    /// Canonical icon names (without aliases).
    public let names: [String]
    private let nodes: [String: [(tag: String, attributes: [String: String])]]
    private let aliases: [String: String]
    private let cache = Mutex<[String: Glyph]>([:])

    private init() {
        var version = "?"
        var nodes: [String: [(String, [String: String])]] = [:]
        var aliases: [String: String] = [:]
        if let url = Bundle.module.url(forResource: "lucide-icons", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            version = root["version"] as? String ?? "?"
            aliases = root["aliases"] as? [String: String] ?? [:]
            for (name, elements) in root["icons"] as? [String: [[Any]]] ?? [:] {
                nodes[name] = elements.compactMap { element in
                    guard element.count == 2, let tag = element[0] as? String,
                          let attributes = element[1] as? [String: String] else { return nil }
                    return (tag, attributes)
                }
            }
        }
        self.version = version
        self.nodes = nodes.mapValues { $0.map { (tag: $0.0, attributes: $0.1) } }
        self.aliases = aliases
        self.names = nodes.keys.sorted()
    }

    /// Canonical Lucide name for a Lucide name or alias, nil when unknown.
    public func canonicalName(_ name: String) -> String? {
        if nodes[name] != nil { return name }
        return aliases[name].flatMap { nodes[$0] != nil ? $0 : nil }
    }

    func glyph(_ name: String) -> Glyph? {
        guard let key = canonicalName(name) else { return nil }
        if let cached = cache.withLock({ $0[key] }) { return cached }
        guard let elements = nodes[key] else { return nil }
        var glyph = Glyph()
        for element in elements {
            let a = element.attributes
            func v(_ k: String) -> CGFloat { CGFloat(Double(a[k] ?? "") ?? 0) }
            var shape = Path()
            switch element.tag {
            case "path":
                shape = SVGPath.parse(a["d"] ?? "")
            case "circle":
                let r = v("r")
                shape.addEllipse(in: CGRect(x: v("cx") - r, y: v("cy") - r, width: 2 * r, height: 2 * r))
            case "ellipse":
                shape.addEllipse(in: CGRect(x: v("cx") - v("rx"), y: v("cy") - v("ry"),
                                            width: 2 * v("rx"), height: 2 * v("ry")))
            case "rect":
                let rect = CGRect(x: v("x"), y: v("y"), width: v("width"), height: v("height"))
                let rx = a["rx"] != nil ? v("rx") : v("ry")
                let ry = a["ry"] != nil ? v("ry") : rx
                shape.addRoundedRect(in: rect, cornerSize: CGSize(width: rx, height: ry))
            case "line":
                shape.move(to: CGPoint(x: v("x1"), y: v("y1")))
                shape.addLine(to: CGPoint(x: v("x2"), y: v("y2")))
            case "polyline", "polygon":
                let points = SVGPath.points(a["points"] ?? "")
                shape.addLines(points)
                if element.tag == "polygon" { shape.closeSubpath() }
            default:
                continue
            }
            if a["fill"] == "currentColor" {
                glyph.fill.addPath(shape)
            }
            glyph.stroke.addPath(shape)
        }
        cache.withLock { $0[key] = glyph }
        return glyph
    }
}

/// Material Symbols names used in the mockups → Lucide. Names not listed here are looked up in
/// Lucide directly, so `Icon("leaf")` and `Icon("eco")` both work.
public enum MarginIcons {
    public static let materialToLucide: [String: String] = [
        "account_balance": "landmark", "groups": "users",
        "add_box": "square-plus", "arrow_downward": "arrow-down", "backspace": "delete", "bedtime": "moon", "block": "ban", "call_split": "split", "check_circle": "circle-check", "cloud_done": "cloud-check", "compress": "fold-vertical", "content_copy": "copy", "content_cut": "scissors", "content_paste": "clipboard-paste", "content_paste_go": "clipboard-type", "create_new_folder": "folder-plus", "dashboard_customize": "layout-template", "document_scanner": "scan-text", "drive_folder_upload": "folder-up", "edit_calendar": "calendar-cog", "event_busy": "calendar-x", "format_align_left": "align-left", "format_bold": "bold", "format_clear": "remove-formatting", "format_h1": "heading-1", "format_h2": "heading-2", "format_h3": "heading-3", "format_italic": "italic", "format_quote": "quote", "horizontal_split": "rows-2", "ios_share": "share", "keyboard_tab": "arrow-right-to-line", "keyboard_tab_rtl": "arrow-left-to-line", "last_page": "chevrons-right", "layers_clear": "layers", "link_off": "unlink", "logout": "log-out", "my_location": "locate-fixed", "new_releases": "badge-check", "north_east": "arrow-up-right", "note": "sticky-note", "note_add": "file-plus", "open_in_full": "maximize-2", "pause_circle": "circle-pause", "photo_size_select_large": "image-up", "refresh": "refresh-cw", "restart_alt": "rotate-ccw", "search_off": "search-x", "select_all": "text-select", "sentiment_satisfied": "smile", "short_text": "text", "sort": "arrow-up-down", "strikethrough_s": "strikethrough", "subtitles": "captions", "tab": "app-window", "thumb_up": "thumbs-up", "unfold_less": "fold-vertical", "vertical_align_bottom": "arrow-down-to-line", "vertical_align_top": "arrow-up-to-line", "vertical_split": "columns-2", "visibility": "eye", "visibility_off": "eye-off", "account_circle": "circle-user", "extension": "puzzle", "folder_open": "folder-open",
        "swap_horiz": "arrow-left-right", "login": "log-in", "laptop_mac": "laptop", "unarchive": "archive-restore", "check": "check", "download": "download", "lightbulb": "lightbulb", "filter_list": "list-filter", "merge": "merge", "hub": "network", "wb_twilight": "sunset", "add": "plus", "add_circle": "circle-plus",
        "add_link": "link-2", "add_task": "list-plus", "alternate_email": "at-sign",
        "arrow_back": "arrow-left", "arrow_forward": "arrow-right", "arrow_upward": "arrow-up",
        "article": "file-text", "assignment": "clipboard-list", "attach_file": "paperclip",
        "auto_awesome": "sparkles", "balance": "scale", "bar_chart": "chart-column", "bolt": "zap",
        "bookmark": "bookmark", "calendar_today": "calendar", "call_made": "arrow-up-right",
        "call_received": "arrow-down-left", "category": "shapes", "center_focus_weak": "scan",
        "change_history": "triangle", "check_box": "square-check",
        "check_box_outline_blank": "square", "chevron_left": "chevron-left",
        "chevron_right": "chevron-right", "close": "x", "cloud_off": "cloud-off", "code": "code",
        "date_range": "calendar-range", "delete": "trash-2", "description": "file-text",
        "dock_to_left": "panel-right", "drive_file_move": "folder-input", "eco": "leaf",
        "edit": "pencil", "edit_note": "notebook-pen", "edit_square": "square-pen",
        "error": "circle-alert", "event": "calendar-days", "event_repeat": "calendar-sync",
        "event_upcoming": "calendar-clock", "expand_more": "chevron-down", "folder": "folder",
        "functions": "sigma", "genetics": "dna", "grid_view": "layout-grid", "help": "circle-help",
        "history": "history", "home": "house", "image": "image", "inbox": "inbox", "info": "info",
        "ink_highlighter": "highlighter", "inventory_2": "archive", "keyboard": "keyboard",
        "language": "globe", "light_mode": "sun", "link": "link", "list": "list",
        "location_on": "map-pin", "menu_book": "book-open", "mic": "mic", "more_horiz": "ellipsis",
        "notes": "text-align-start", "open_in_new": "external-link", "palette": "palette",
        "percent": "percent", "person": "user", "picture_as_pdf": "file-type",
        "psychology": "brain", "public": "globe", "push_pin": "pin", "quiz": "file-question-mark",
        "remove": "minus", "schedule": "clock", "school": "graduation-cap",
        "science": "flask-conical", "search": "search", "sell": "tag", "settings": "settings",
        "share": "share-2", "side_navigation": "panel-left", "smartphone": "smartphone",
        "style": "layers", "subdirectory_arrow_right": "corner-down-right",
        "summarize": "scroll-text", "swap_vert": "arrow-up-down", "sync": "refresh-cw",
        "table": "table", "tag": "hash", "task_alt": "circle-check", "text_fields": "type",
        "timer": "timer", "toc": "table-of-contents", "trending_up": "trending-up",
        "tune": "sliders-horizontal", "upload_file": "file-up", "viewport": "scan",
    ]

    /// Names drawn without a glyph since launch (debugging and `IconCoverageTests`).
    @MainActor static private(set) var missing: Set<String> = []
    @MainActor static func reportMissing(_ name: String) { missing.insert(name) }

    /// Lucide name for a Material or Lucide name, nil when the icon does not exist.
    public static func lucideName(for name: String) -> String? {
        LucideIcons.shared.canonicalName(materialToLucide[name] ?? name)
    }
}

/// Stroke weight. Thinner than the mockups' Material weight 300 (user's call, like the ChatGPT app).
public enum IconWeight: Sendable {
    case light, regular, bold

    /// Stroke width in the 24-unit viewBox.
    var viewBoxStroke: CGFloat {
        switch self {
        case .light: 1.25
        case .regular: 1.5
        case .bold: 2
        }
    }
}

/// A Lucide icon drawn as vector paths. Colour comes from `color` or the foreground style.
public struct Icon: View {
    let name: String
    let size: CGFloat
    let weight: IconWeight
    let color: Color?

    public init(_ name: String, size: CGFloat = 20, weight: IconWeight = .regular, color: Color? = nil) {
        self.name = name
        self.size = size
        self.weight = weight
        self.color = color
    }

    /// Whether `name` is one emoji rather than an icon name (a course icon can be either).
    nonisolated public static func isEmoji(_ name: String) -> Bool { CoursePalette.isEmoji(name) }

    public var body: some View {
        if Self.isEmoji(name) {
            Text(name)
                .font(.system(size: size * 0.86))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            glyphView
        }
    }

    @ViewBuilder private var glyphView: some View {
        let glyph = MarginIcons.lucideName(for: name).flatMap { LucideIcons.shared.glyph($0) }
        let scale = size / 24
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let shape = ZStack {
            if let glyph {
                glyph.stroke.applying(transform)
                    .stroke(style: StrokeStyle(lineWidth: weight.viewBoxStroke * scale, lineCap: .round, lineJoin: .round))
                glyph.fill.applying(transform).fill()
            } else {
                // An empty name keeps the icon's space (menu rows without an icon); an unknown one
                // stays empty too and is recorded, so tests catch it (`IconCoverageTests`).
                let _ = name.isEmpty ? () : MarginIcons.reportMissing(name)
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        // Without an explicit colour the icon inherits the surrounding foreground style
        // (white inside a primary button, blue in an active chip, …).
        if let color {
            shape.foregroundStyle(color)
        } else {
            shape
        }
    }
}
