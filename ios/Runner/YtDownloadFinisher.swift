import AVFoundation
import CoreMedia
import UIKit

/// Turns a YouTube download into a proper music file.
///
/// YouTube serves audio as a streaming (DASH, fragmented) MP4 with no tags.
/// AVFoundation's passthrough export rewrites it as a plain .m4a — the AAC
/// copied as is, no re-encode — and writes the tags in the same pass: title,
/// artists, album, album artist, year, track, lyrics and cover. (Android does
/// the same in two steps; see YtDownloadFinisher.java.)
enum YtDownloadFinisher {
    /// Writes `src` repackaged and tagged to `dst`; `completion` gets nil on
    /// success, else what went wrong. `dst` is removed on failure.
    static func finish(src: String, dst: String, tags: [String: Any],
                       completion: @escaping (String?) -> Void) {
        let out = URL(fileURLWithPath: dst)
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: URL(fileURLWithPath: src))
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough) else {
            completion("no export session")
            return
        }
        session.outputURL = out
        session.outputFileType = .m4a
        session.metadata = metadata(tags)
        session.exportAsynchronously {
            if session.status == .completed {
                completion(nil)
            } else {
                try? FileManager.default.removeItem(at: out)
                completion(session.error?.localizedDescription ?? "export ended \(session.status.rawValue)")
            }
        }
    }

    static func metadata(_ tags: [String: Any]) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func text(_ id: AVMetadataIdentifier, _ key: String) {
            if let value = tags[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                items.append(item(id, value as NSString))
            }
        }
        text(.commonIdentifierTitle, "title")
        text(.commonIdentifierArtist, "artist")
        text(.commonIdentifierAlbumName, "album")
        text(.iTunesMetadataAlbumArtist, "albumArtist")
        text(.iTunesMetadataReleaseDate, "year")
        text(.iTunesMetadataLyrics, "lyrics")
        if let track = (tags["track"] as? String).flatMap({ Int($0) }) {
            let total = (tags["trackTotal"] as? String).flatMap({ Int($0) }) ?? 0
            // iTunes 'trkn': two reserved bytes, track, total, two reserved.
            let bytes: [UInt8] = [0, 0, UInt8((track >> 8) & 0xff), UInt8(track & 0xff),
                                  UInt8((total >> 8) & 0xff), UInt8(total & 0xff), 0, 0]
            items.append(item(.iTunesMetadataTrackNumber, Data(bytes) as NSData,
                              kCMMetadataBaseDataType_RawData as String))
        }
        if let path = tags["coverPath"] as? String, var data = FileManager.default.contents(atPath: path) {
            if (tags["cropCover"] as? Bool) == true, let square = cropSquare(data) {
                data = square
            }
            items.append(item(.commonIdentifierArtwork, data as NSData,
                              kCMMetadataBaseDataType_JPEG as String))
        }
        return items
    }

    private static func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol,
                             _ dataType: String? = nil) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value
        if let dataType { item.dataType = dataType }
        item.extendedLanguageTag = "und"
        return item
    }

    /// A 16:9 video thumbnail's middle square, as JPEG.
    static func cropSquare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        if w == h { return data }
        let side = min(w, h)
        guard let cropped = cg.cropping(to: CGRect(x: (w - side) / 2, y: (h - side) / 2,
                                                   width: side, height: side)) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.92)
    }

    /// Puts each finished `replacement` in place of its `path` (the app's own
    /// files in Documents), consuming the replacement. Path → success.
    static func replace(_ files: [[String: String]]) -> [String: Bool] {
        var done: [String: Bool] = [:]
        for file in files {
            guard let path = file["path"], let replacement = file["replacement"] else { continue }
            do {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                          withItemAt: URL(fileURLWithPath: replacement))
                done[path] = true
            } catch {
                NSLog("YtDownloadFinisher: could not replace \(path): \(error)")
                done[path] = false
            }
        }
        return done
    }
}
