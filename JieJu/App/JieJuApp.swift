import SwiftUI

@main
struct JieJuApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1080, height: 720)
    }
}
