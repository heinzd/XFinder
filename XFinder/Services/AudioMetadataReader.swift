import AVFoundation
import Foundation

enum AudioMetadataReader {
    private struct AlbumFolderInfo {
        let artist: String
        let album: String
        let year: String
        let baseNameWithoutYear: String
    }

    private enum FolderArtworkRule: CaseIterable {
        case conventionalCoverName
        case exactDirectoryNameWithoutYear
        case normalizedDirectoryNameWithoutYear
        case firstNonBackImage
    }

    static func track(at url: URL) async -> AudioTrack {
        let asset = AVURLAsset(url: url)
        let folderInfo = albumFolderInfo(for: url.deletingLastPathComponent())

        do {
            let metadata = try await asset.load(.commonMetadata)
            let duration = try await asset.load(.duration).seconds
            let title = await stringValue(for: .commonIdentifierTitle, in: metadata)
            let artist = await stringValue(for: .commonIdentifierArtist, in: metadata)
            let embeddedAlbum = await stringValue(
                for: .commonIdentifierAlbumName,
                in: metadata
            )
            let embeddedArtwork = await dataValue(
                for: .commonIdentifierArtwork,
                in: metadata
            )

            return AudioTrack(
                url: url,
                title: title ?? url.deletingPathExtension().lastPathComponent,
                artist: artist ?? folderInfo?.artist,
                album: embeddedAlbum ?? folderInfo?.album,
                year: folderInfo?.year,
                artworkData: embeddedArtwork ?? folderArtworkData(beside: url),
                duration: duration.isFinite ? duration : 0
            )
        } catch {
            return AudioTrack(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                artist: folderInfo?.artist,
                album: folderInfo?.album,
                year: folderInfo?.year,
                artworkData: folderArtworkData(beside: url),
                duration: 0
            )
        }
    }

    private static func stringValue(
        for identifier: AVMetadataIdentifier,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: identifier
        ).first else { return nil }
        return try? await item.load(.stringValue)
    }

    private static func dataValue(
        for identifier: AVMetadataIdentifier,
        in metadata: [AVMetadataItem]
    ) async -> Data? {
        guard let item = AVMetadataItem.metadataItems(
            from: metadata,
            filteredByIdentifier: identifier
        ).first else { return nil }
        return try? await item.load(.dataValue)
    }

    private static func folderArtworkData(beside audioURL: URL) -> Data? {
        let folder = audioURL.deletingLastPathComponent()
        let supportedExtensions = [
            "jpg", "jpeg", "png", "heic", "heif",
            "webp", "tif", "tiff", "bmp", "gif"
        ]

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let imageFiles = files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                let left = supportedExtensions.firstIndex(
                    of: $0.pathExtension.lowercased()
                ) ?? .max
                let right = supportedExtensions.firstIndex(
                    of: $1.pathExtension.lowercased()
                ) ?? .max
                return left < right
            }

        let folderInfo = albumFolderInfo(for: folder)

        for rule in FolderArtworkRule.allCases {
            let match: URL?

            switch rule {
            case .conventionalCoverName:
                match = imageFiles.first {
                    baseName(of: $0).caseInsensitiveCompare("cover") == .orderedSame
                }

            case .exactDirectoryNameWithoutYear:
                guard let expected = folderInfo?.baseNameWithoutYear else {
                    continue
                }
                match = imageFiles.first {
                    baseName(of: $0).caseInsensitiveCompare(expected) == .orderedSame
                }

            case .normalizedDirectoryNameWithoutYear:
                guard let expected = folderInfo?.baseNameWithoutYear else {
                    continue
                }
                let normalizedExpected = normalizedCoverName(expected)
                match = imageFiles.first {
                    normalizedCoverName(baseName(of: $0))
                        .caseInsensitiveCompare(normalizedExpected) == .orderedSame
                }

            case .firstNonBackImage:
                match = imageFiles.first {
                    !baseName(of: $0)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .hasSuffix("back")
                }
            }

            if let match, let data = try? Data(contentsOf: match) {
                return data
            }
        }

        return nil
    }

    private static func baseName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func normalizedCoverName(_ name: String) -> String {
        let normalizedDashes = name
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "−", with: "-")

        return normalizedDashes
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: " - ", with: "-")
    }

    private static func albumFolderInfo(for folder: URL) -> AlbumFolderInfo? {
        let folderName = folder.lastPathComponent
        let pattern = #"^(\d+\.\s+(.+?)\s+[-–—−]\s+(.+?))\s+(?:\[(\d{4})\]|\((\d{4})\))$"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let source = folderName as NSString
        let range = NSRange(location: 0, length: source.length)
        guard
            let match = expression.firstMatch(in: folderName, range: range),
            match.range == range
        else { return nil }

        let yearRange = match.range(at: 4).location != NSNotFound
            ? match.range(at: 4)
            : match.range(at: 5)

        return AlbumFolderInfo(
            artist: source.substring(with: match.range(at: 2)),
            album: source.substring(with: match.range(at: 3)),
            year: source.substring(with: yearRange),
            baseNameWithoutYear: source.substring(with: match.range(at: 1))
        )
    }
}

