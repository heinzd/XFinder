import Foundation

struct AudioTrack: Sendable {
    let url: URL
    let title: String
    let artist: String?
    let album: String?
    let year: String?
    let artworkData: Data?
    let duration: TimeInterval
}

