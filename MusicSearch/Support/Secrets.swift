import Foundation

/// Reads secrets that should not be committed to source control.
///
/// Provide a Last.fm API key in either of two ways:
/// 1. A `LASTFM_API_KEY` environment variable on the Run scheme (handy for dev), or
/// 2. A `Secrets.plist` file in the app target containing a `LASTFM_API_KEY`
///    string. `Secrets.plist` is git-ignored; copy `Secrets.example.plist`
///    to `Secrets.plist` and fill in your key.
///
/// Get a free key at https://www.last.fm/api/account/create
enum Secrets {
    static var lastFMAPIKey: String? {
        if let env = ProcessInfo.processInfo.environment["LASTFM_API_KEY"],
           !env.isEmpty {
            return env
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["LASTFM_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }
}
