import SwiftUI
import MusicKit

/// A single album cell in the results grid: artwork with a play button and an
/// info button that reveals the model's rationale for the match in a popover.
struct AlbumGridItem: View {
    let result: SearchResult
    var onPlay: () -> Void

    @State private var showReason = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
                .overlay(alignment: .topLeading) { infoButton }
                .overlay(alignment: .bottomTrailing) { playButton }

            Text(result.album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(result.album.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = result.album.artwork {
            ArtworkImage(artwork, width: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .padding(6)
        .accessibilityLabel("Play \(result.album.title)")
    }

    @ViewBuilder
    private var infoButton: some View {
        if !result.reason.isEmpty {
            Button {
                showReason = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(6)
            .accessibilityLabel("Why \(result.album.title) matched")
            .popover(isPresented: $showReason) {
                reasonPopover
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var reasonPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.album.title)
                .font(.headline)
            Text(result.album.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Text(result.reason)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 260)
    }
}
