import SwiftUI
import MusicKit

/// Routes between the "connect to Apple Music" screen and the main search
/// experience based on authorization status.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.isAuthorized {
                SearchView()
            } else {
                ConnectView()
            }
        }
        .animation(.default, value: appModel.authorizationStatus)
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
