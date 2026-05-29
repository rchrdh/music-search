import SwiftUI

@main
struct MusicSearchApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task {
                    // Pick up an existing authorization decision on launch.
                    await appModel.refreshAuthorizationStatus()
                }
        }
    }
}
