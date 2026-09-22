import AppKit
import FractalEngine

public final class RenderCancellation: @unchecked Sendable {
    let pointer: OpaquePointer
    public init() { pointer = mdb_cancel_create()! }
    public func cancel() { mdb_cancel_set(pointer) }
    public var isCancelled: Bool { mdb_cancel_is_set(pointer) != 0 }
    deinit { mdb_cancel_destroy(pointer) }
}

public struct RenderedImage {
    public let image: CGImage
    public let seconds: Double
    public func encoded(format: ImageFormat, jpegQuality: Double = 0.95) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: image.width, height: image.height)
        guard let data = bitmap.representation(using: format == .png ? .png : .jpeg,
                                               properties: format == .png ? [:] : [.compressionFactor: jpegQuality]) else {
            throw MandelbrotError.renderFailed
        }
        return data
    }
}

public enum Renderer {
    /// Synchronous worker API. Call from a background queue; cancellation is cooperative.
    public static func render(view: ViewState, width: Int, height: Int, samples: Int = 1,
                              cancellation: RenderCancellation = RenderCancellation(),
                              progress: ((Double) -> Void)? = nil) throws -> RenderedImage? {
        _ = try view.validated()
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 40_000_000, (1...2).contains(samples) else { throw MandelbrotError.invalidExport }
        if cancellation.isCancelled { return nil }
        let start = Date()
        let byteCount = width * height * 4
        guard let allocation = calloc(byteCount, 1) else { throw MandelbrotError.renderFailed }
        let pixels = allocation.assumingMemoryBound(to: UInt8.self)
        let tileRows = 8
        let tileCount = (height + tileRows - 1) / tileRows
        let lock = NSLock()
        var complete = 0
        DispatchQueue.concurrentPerform(iterations: tileCount) { tile in
            guard !cancellation.isCancelled else { return }
            let first = tile * tileRows
            mdb_render_rows(pixels, Int32(width), Int32(height), Int32(first), Int32(min(height, first + tileRows)),
                            view.centerX, view.centerY, view.span, Int32(view.iterations), view.colorPeriod,
                            view.palette.index, Int32(samples), cancellation.pointer)
            if let progress {
                lock.lock()
                complete += 1
                progress(Double(complete) / Double(tileCount))
                lock.unlock()
            }
        }
        guard !cancellation.isCancelled else { free(allocation); return nil }
        // Transfer the allocation to Core Graphics without making a second full image copy.
        guard let provider = CGDataProvider(dataInfo: nil, data: allocation, size: byteCount,
                                            releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }) else {
            free(allocation); throw MandelbrotError.renderFailed
        }
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw MandelbrotError.renderFailed
        }
        return RenderedImage(image: image, seconds: Date().timeIntervalSince(start))
    }
}
