import SwiftUI
import UIKit
import MusicKit

/// Opening screen: invites the user to connect their Apple Music library.
struct ConnectView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Music Search")
                    .font(.largeTitle.bold())
                Text("Search your Apple Music library in plain language — by mood, language, style, or anything else.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        isConnecting = true
                        await appModel.connect()
                        isConnecting = false
                    }
                } label: {
                    HStack {
                        if isConnecting { ProgressView().tint(.white) }
                        Text(isConnecting ? "Connecting…" : "Connect to Apple Music")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnecting)

                deniedMessage
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var deniedMessage: some View {
        switch appModel.authorizationStatus {
        case .denied:
            VStack(spacing: 8) {
                Text("Access to Apple Music was denied. Enable it in Settings to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.footnote.weight(.semibold))
                }
            }
        case .restricted:
            Text("Apple Music access is restricted on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

#Preview {
    ConnectView()
        .environment(AppModel())
}
