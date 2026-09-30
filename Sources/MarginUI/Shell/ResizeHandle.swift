import SwiftUI

/// Invisible 8 px grip on a panel edge: drag to resize, double-click to restore the default.
/// Shows the column-resize pointer on hover.
struct ResizeHandle: View {
    let edge: HorizontalEdge
    let width: CGFloat
    let onChange: (CGFloat) -> Void
    let onReset: () -> Void
    @State private var startWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            // Centre the grip on the border line.
            .offset(x: edge == .trailing ? 4 : -4)
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        // A trailing edge grows to the right, a leading edge (inspector) to the left.
                        let delta = edge == .trailing ? value.translation.width : -value.translation.width
                        onChange(start + delta)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onTapGesture(count: 2, perform: onReset)
            .accessibilityHidden(true)
    }
}
