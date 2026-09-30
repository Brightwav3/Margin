import MarginCore
import SwiftUI

/// Properties of a note (3a): „Properties“, a 160 px key column, typed values, „Add property“.
/// Values are edited in place and written to the frontmatter through `PropertyService` (M6-05.U).
struct PropertiesPanel: View {
    let model: NoteEditorModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Properties").marginFont(16, .semibold).padding(.bottom, 8)
            // `id:` is Margin's stable note id (spec 05 §7), not something to edit.
            ForEach(model.properties.filter { $0.key != "id" }) { property in
                PropertyLine(property: property, model: model)
            }
            Button { adding = true } label: {
                HStack(spacing: 8) {
                    Icon("add", size: 18, color: MarginColor.textSecondary)
                    Text("Add property")
                }
                .marginFont(MarginTextSize.base)
                .foregroundStyle(MarginColor.textSecondary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .disabled(model.isDraft)
            .help(model.isDraft ? "Write something first; the note is created on the first save" : "")
            .popover(isPresented: $adding, arrowEdge: .bottom) {
                AddPropertyPopover(model: model) { adding = false }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .padding(.bottom, 18)
    }
}

enum PropertyIcons {
    static func icon(_ type: PropertyType) -> String {
        switch type {
        case .date: "calendar_today"
        case .text: "notes"
        case .tags: "sell"
        case .number: "tag"
        case .checkbox: "check_box"
        case .list: "list"
        case .link: "link"
        }
    }
}

private struct PropertyLine: View {
    let property: NoteProperty
    let model: NoteEditorModel
    @State private var editing = false
    @State private var draft = ""
    @Environment(Workspace.self) private var workspace

    var body: some View {
        PropertyRow(icon: PropertyIcons.icon(property.type), key: property.key) {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .marginFont(MarginTextSize.base)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
            } else {
                value
                    .contentShape(Rectangle())
                    .onTapGesture { begin() }
            }
        }
        .contextMenu {
            Button("Edit") { begin() }
            Button("Remove property", role: .destructive) {
                Task { await model.removeProperty(property.key) }
            }
        }
    }

    @ViewBuilder
    private var value: some View {
        switch property.value {
        case .list(let items) where property.type == .tags || property.type == .list:
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in PropertyTag(item.display) }
            }
        case .bool(let b):
            CheckboxView(isOn: Binding(get: { b }, set: { v in Task { await model.setProperty(property.key, .bool(v)) } }))
        case .date(let d):
            HStack(spacing: 8) {
                Icon("calendar_today", size: 16, color: MarginColor.textSecondary)
                Text(String(format: "%02d.%02d.%04d", d.day, d.month, d.year)).monospacedDigit().tracking(0.3)
            }
        case .string(let s) where s.hasPrefix("[[") && s.hasSuffix("]]"):
            let target = String(s.dropFirst(2).dropLast(2))
            Button(target) { workspace.openLink(target, from: model.courseID) }
                .buttonStyle(.plain)
                .foregroundStyle(MarginColor.accent)
                .underline()
        default:
            Text(property.value.display.isEmpty ? "Empty" : property.value.display)
                .foregroundStyle(property.value.display.isEmpty ? MarginColor.textTertiary : MarginColor.ink)
        }
    }

    private func begin() {
        guard property.type != .checkbox else { return }
        if case .date(let d) = property.value { draft = d.iso } else { draft = property.value.display }
        editing = true
    }

    private func commit() {
        editing = false
        let value = PropertyParsing.value(draft, type: property.type)
        Task { await model.setProperty(property.key, value) }
    }
}

/// Text typed into a property value → a typed frontmatter value.
enum PropertyParsing {
    static func value(_ text: String, type: PropertyType) -> FrontmatterValue {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch type {
        case .date:
            if let d = LocalDate(iso: t) { return .date(d) }
            let parts = t.split(whereSeparator: { $0 == "." || $0 == "/" }).compactMap { Int($0) }
            if parts.count == 3, let d = LocalDate(year: parts[2], month: parts[1], day: parts[0]) { return .date(d) }
            return .string(t)
        case .number:
            return Double(t.replacingOccurrences(of: ",", with: ".")).map(FrontmatterValue.number) ?? .string(t)
        case .checkbox:
            return .bool(["yes", "true", "1", "x"].contains(t.lowercased()))
        case .tags, .list:
            return .list(t.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) }.filter { $0.display != "" })
        case .link:
            return .string(t.hasPrefix("[[") ? t : "[[\(t)]]")
        case .text:
            return .string(t)
        }
    }

    static func empty(_ type: PropertyType, today: LocalDate) -> FrontmatterValue {
        switch type {
        case .date: .date(today)
        case .number: .number(0)
        case .checkbox: .bool(false)
        case .tags, .list: .list([])
        case .link, .text: .string("")
        }
    }
}

/// 1e Add property: name and type picker.
struct AddPropertyPopover: View {
    let model: NoteEditorModel
    let close: () -> Void
    @State private var name = ""
    @State private var type: PropertyType = .text
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Property name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            PopupSection(title: "Property type")
            ForEach(PropertyType.allCases) { t in
                MenuRow(title: t.displayName, icon: PropertyIcons.icon(t), checked: t == type) { type = t }
            }
            HStack {
                Spacer()
                MarginButton("Cancel", size: .small, action: close)
                MarginButton("Add", kind: .primary, size: .small, action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .frame(width: 260)
        .onAppear {
            if let known = model.propertyTypes.first(where: { $0.key == name })?.value { type = known }
        }
    }

    private func add() {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let value = PropertyParsing.empty(model.propertyTypes[key] ?? type, today: workspace.env.clock.today)
        close()
        Task { await model.setProperty(key, value) }
    }
}
