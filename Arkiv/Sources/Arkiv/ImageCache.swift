import AppKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()

    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let previewCache = NSCache<NSURL, NSImage>()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "net.arkivverket.arkiv.ImageDecode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 5
        return queue
    }()

    private init() {
        thumbnailCache.countLimit = 1_500
        previewCache.countLimit = 80
    }

    func thumbnail(for url: URL, side: CGFloat, completion: @escaping (NSImage?) -> Void) {
        let key = cacheKey(url: url, size: Int(side))
        if let cached = thumbnailCache.object(forKey: key) {
            completion(cached)
            return
        }

        queue.addOperation { [thumbnailCache] in
            let image = Self.decode(url: url, maxPixel: Int(side * 2))
            if let image {
                thumbnailCache.setObject(image, forKey: key)
            }
            OperationQueue.main.addOperation {
                completion(image)
            }
        }
    }

    func preview(for url: URL, maxPixel: Int = 2600, completion: @escaping (NSImage?) -> Void) {
        let key = cacheKey(url: url, size: maxPixel)
        if let cached = previewCache.object(forKey: key) {
            completion(cached)
            return
        }

        queue.addOperation { [previewCache] in
            let image = Self.decode(url: url, maxPixel: maxPixel)
            if let image {
                previewCache.setObject(image, forKey: key)
            }
            OperationQueue.main.addOperation {
                completion(image)
            }
        }
    }

    func warm(_ urls: [URL], side: CGFloat) {
        for url in urls {
            thumbnail(for: url, side: side) { _ in }
        }
    }

    private func cacheKey(url: URL, size: Int) -> NSURL {
        NSURL(fileURLWithPath: "\(url.path)#\(size)")
    }

    private static func decode(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
