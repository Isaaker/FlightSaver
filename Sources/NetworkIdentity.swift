import Foundation

/// Shared application identity for remote data providers.
/// The contact URL is intentionally public so providers can reach the maintainer
/// if this client causes problems or needs to be identified.
enum NetworkIdentity {
    static let userAgent = "FlightSaver/1.1.1 (+https://github.com/Isaaker/FlightSaver)"
}
