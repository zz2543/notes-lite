import AppKit
import AVFoundation
import ImageIO

/// An attachment shown in place of `![[…]]` / `![](…)` on its own line.
final class Embed: NSObject {
    enum Kind { case image, video, other }
    let target: String
    let url: URL?
    let kind: Kind
    /// Set once the picture (or the video's first frame) is decoded.
    var image: NSImage?
    var failed = false

    init(target: String, url: URL?, kind: Kind) {
        self.target = target
        self.url = url
        self.kind = kind
    }

    static func kind(of name: String) -> Kind {
        let ext = (name.split(separator: "|").first.map(String.init) ?? name).lowercased()
        let e = (ext as NSString).pathExtension
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "svg", "avif"].contains(e) { return .image }
        if ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(e) { return .video }
        return .other
    }

    /// Height the picture takes at `width`, capped so one image never fills the whole window.
    func height(fitting width: CGFloat) -> CGFloat {
        guard let image, image.size.width > 0 else { return failed ? 34 : 120 }
        let w = min(width, image.size.width)
        return min(480, (w * image.size.height / image.size.width).rounded())
    }

    func drawRect(in frame: CGRect) -> CGRect {
        guard let image, image.size.width > 0 else { return CGRect(x: frame.minX, y: frame.minY, width: min(frame.width, 260), height: frame.height) }
        let h = frame.height
        let w = min(frame.width, h * image.size.width / image.size.height)
        return CGRect(x: frame.minX, y: frame.minY, width: w, height: h)
    }
}

/// Decodes embeds off the main thread and remembers them per file, so re-styling a line is free.
final class EmbedCache {
    static let shared = EmbedCache()
    private var cache: [URL: Embed] = [:]
    private var waiting: [URL: [() -> Void]] = [:]
    private let queue = DispatchQueue(label: "twain.embeds", qos: .userInitiated, attributes: .concurrent)

    /// The embed for `url`, loading it if needed; `ready` runs on the main queue once it is.
    func embed(target: String, url: URL?, ready: @escaping () -> Void) -> Embed {
        let kind = Embed.kind(of: target)
        guard let url, kind != .other else {
            let e = Embed(target: target, url: url, kind: kind)
            e.failed = url == nil
            return e
        }
        if let e = cache[url] { return e }
        let e = Embed(target: target, url: url, kind: kind)
        cache[url] = e
        waiting[url, default: []].append(ready)
        queue.async {
            let img = kind == .video ? Self.videoFrame(url) : Self.thumbnail(url)
            DispatchQueue.main.async {
                e.image = img
                e.failed = img == nil
                for w in self.waiting.removeValue(forKey: url) ?? [] { w() }
            }
        }
        return e
    }

    /// Drops a file whose content changed on disk.
    func forget(_ url: URL) { cache[url] = nil }

    /// Downsampled to what the page can show; keeps memory flat for big photos.
    static func thumbnail(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "svg" { return NSImage(contentsOf: url) }
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else {
            return url.isFileURL ? nil : NSImage(contentsOf: url)
        }
        let thumbOpts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: 1600]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }

    static func videoFrame(_ url: URL) -> NSImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1600, height: 1600)
        let sem = DispatchSemaphore(value: 0)
        var out: CGImage?
        gen.generateCGImageAsynchronously(for: CMTime(seconds: 0.5, preferredTimescale: 600)) { img, _, _ in
            out = img
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 8)
        guard let cg = out else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }
}
