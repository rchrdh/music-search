import SwiftUI
import MusicKit

/// A single album cell in the results grid: artwork, title, artist, and the
/// model's short rationale for why it matched.
struct AlbumGridItem: View {
    let result: SearchResult
    var onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                artwork
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(6)
                .accessibilityLabel("Play \(result.album.title)")
            }

            Text(result.album.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(result.album.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !result.reason.isEmpty {
                Text(result.reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
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
}
