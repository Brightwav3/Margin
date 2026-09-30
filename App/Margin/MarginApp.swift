import MarginPlatform
import MarginUI
import SwiftUI

@main
struct MarginApp: App {
    private let requestedScreen = MarginScreens.requestedID()

    var body: some Scene {
        WindowGroup {
            if let id = requestedScreen, let screen = MarginScreens.screen(id: id) {
                // `--screen <id>`: open one screen at mockup size.
                screen.view()
                    .frame(width: MarginScreens.size.width, height: MarginScreens.size.height)
            } else {
                ScreenGallery()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(requestedScreen == nil ? .automatic : .contentSize)
    }
}
