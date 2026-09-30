import MarginCore
import SwiftUI

/// Sidebar and inspector of a note page: the course's navigation and Notes space, and the note
/// inspector (Outline, Backlinks, Outgoing links, All properties) — M6-09.U.
extension Workspace {
    func editorModel(_ route: Route) -> NoteEditorModel {
        model(route.key) {
            let target: NoteEditorModel.Target = switch route {
            case .draft(let c, let d, let t): .draft(course: c, date: d, title: t)
            case .note(let id): .note(id)
            default: .note("")
            }
            let m = NoteEditorModel(env: env, target: target)
            m.readableLineLength = editorDefaults.readableLineLength
            m.setMode(editorDefaults.mode)
            m.showsProperties = editorDefaults.showProperties
            m.onLoaded = { [weak self] summary in self?.retitle(route: .note(summary.id), title: summary.title) }
            m.onCreated = { [weak self, weak m] summary in
                guard let self, let m else { return }
                // The draft tab now shows the note; keep the model under its new route.
                self.adopt(m, from: route, to: .note(summary.id))
                self.replaceActive(with: .note(summary.id), title: summary.title)
                Task { await self.courses.load() }
            }
            return m
        }
    }

    func noteChrome(_ route: Route) -> PageChrome {
        let m = editorModel(route)
        let courseID = m.courseID ?? {
            if case .note(let id) = route { return courses.courseID(ofNote: id) } else { return nil }
        }()
        var sidebar: SidebarContent
        if let courseID {
            sidebar = courseChrome(courseID).sidebar
            // The note sits in the course's Notes space.
            if sidebar.notes != nil, shell.sidebarPage == .navigation, !notesPageShown.contains(route.key) {
                notesPageShown.insert(route.key)
                shell.sidebarPage = .notes
            }
        } else {
            sidebar = coursesSidebar
        }
        return PageChrome(sidebar: sidebar, inspector: noteInspector(m))
    }

    func noteInspector(_ m: NoteEditorModel) -> InspectorContent {
        let outline = m.outline.map { item in
            InspectorRow(item.text, indent: CGFloat(8 + max(0, item.level - 1) * 14), isBold: item.level == 1) { [weak self] in
                guard let self, let id = m.noteID else { return }
                self.reveal = (id, item.line)
            }
        }
        let backlinks = m.backlinks.map { link in
            InspectorRow(link.sourceTitle, meta: link.context, icon: "description", isLink: true) { [weak self] in
                self?.reveal = (link.sourceNoteID, link.line)
                self?.open(.note(link.sourceNoteID), title: link.sourceTitle)
            }
        }
        let outgoing = m.outgoing.filter { $0.state != .selfLink }.map { link -> InspectorRow in
            let course = link.noteID.flatMap { courses.courseID(ofNote: $0) }.flatMap { courses.course(id: $0)?.name }
            if link.state == .notCreated {
                return InspectorRow(link.target, meta: "Not created yet", icon: "add_circle") { [weak self] in
                    self?.openLink(link.target, from: m.courseID)
                }
            }
            return InspectorRow(link.title ?? link.target, meta: course, icon: "description", isLink: true) { [weak self] in
                if let id = link.noteID { self?.open(.note(id), title: link.title ?? link.target) }
            }
        }
        let properties = m.propertyTypes.sorted { $0.key < $1.key }.map { key, type in
            InspectorRow(key, icon: PropertyIcons.icon(type), count: type.displayName)
        }
        return InspectorContent(
            kind: .note,
            rows: [.outline: outline, .backlinks: backlinks, .outgoing: outgoing, .properties: properties],
            titles: [.backlinks: "Backlinks · \(m.backlinks.count)", .outgoing: "Outgoing links · \(outgoing.count)"],
            agentContext: ("description", m.title), chat: [], suggestions: [], placeholder: "Ask about this note…")
    }
}
