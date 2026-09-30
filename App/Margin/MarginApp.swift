import MarginPlatform
import MarginUI
import SwiftUI

@main
struct MarginApp: App {
    private let requestedScreen = MarginScreens.requestedID()

    var body: some Scene {
        WindowGroup {
            if let id = requestedScreen, let screen = MarginScreens.screen(id: id) {
                // `--screen <id>`: open one screen at mockup size; the window can still be resized,
                // zoomed and made full screen.
                screen.view()
                    .frame(minWidth: 820, idealWidth: MarginScreens.size.width, maxWidth: .infinity,
                           minHeight: 560, idealHeight: MarginScreens.size.height, maxHeight: .infinity)
            } else {
                ScreenGallery()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: MarginScreens.size.width, height: MarginScreens.size.height)
        .windowResizability(.contentMinSize)
    }
}
