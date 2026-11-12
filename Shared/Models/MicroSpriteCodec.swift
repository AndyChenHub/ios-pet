import Compression
import CoreGraphics
import Foundation
import UIKit

/// Encodes and decodes ultra-compact (`~350-450 byte`) 16-color indexed micro-sprites using `COMPRESSION_ZLIB`
/// so custom user-imported spritesheets can animate inside Dynamic Island `ContentState` (< 4 KB budget)
/// and sync end-to-end encrypted to a partner's iPhone without requiring App Group provisioning.
public enum MicroSpriteCodec {
    public static let defaultDimension: Int = 36
    private static let maxCompressedBytes: Int = 2048
    private static let maxDecompressedBytes: Int = 4096

    private static let imageCache: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.countLimit = 128
        return cache
    }()

    /// Quantizes a square sprite frame into a 15-color + transparent 4-bit palette and compresses with zlib.
    public static func encodeFrame(_ cgImage: CGImage, dimension: Int = defaultDimension) -> Data? {
        let dim = max(16, min(48, dimension))
        let pixelCount = dim * dim
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bytesPerRow: dim * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        ctx.interpolationQuality = .high

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = min(CGFloat(dim) / srcW, CGFloat(dim) / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawRect = CGRect(
            x: (CGFloat(dim) - drawW) * 0.5,
            y: (CGFloat(dim) - drawH) * 0.5,
            width: drawW,
            height: drawH
        )
        ctx.draw(cgImage, in: drawRect)

        // Extract unpremultiplied RGB for visible pixels (alpha >= 72)
        var opaquePixels: [(r: Int, g: Int, b: Int)] = []
        opaquePixels.reserveCapacity(pixelCount / 2)
        var unpremul = [(r: UInt8, g: UInt8, b: UInt8, opaque: Bool)](
            repeating: (0, 0, 0, false),
            count: pixelCount
        )

        for i in 0..<pixelCount {
            let base = i * 4
            let a = Int(rgba[base + 3])
            if a >= 72 {
                let r = min(255, (Int(rgba[base]) * 255 + a / 2) / a)
                let g = min(255, (Int(rgba[base + 1]) * 255 + a / 2) / a)
                let b = min(255, (Int(rgba[base + 2]) * 255 + a / 2) / a)
                unpremul[i] = (UInt8(r), UInt8(g), UInt8(b), true)
                opaquePixels.append((r, g, b))
            }
        }

        let palette = buildPalette15(from: opaquePixels)

        // Header: [width, height] (2B) + 15 * RGB (45B) + ceil(dim*dim / 2) packed 4-bit indices
        let packedCount = (pixelCount + 1) / 2
        var raw = [UInt8]()
        raw.reserveCapacity(2 + 45 + packedCount)
        raw.append(UInt8(dim))
        raw.append(UInt8(dim))

        for i in 0..<15 {
            if i < palette.count {
                raw.append(UInt8(clamping: palette[i].r))
                raw.append(UInt8(clamping: palette[i].g))
                raw.append(UInt8(clamping: palette[i].b))
            } else {
                raw.append(0)
                raw.append(0)
                raw.append(0)
            }
        }

        var indices = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount where unpremul[i].opaque {
            let px = unpremul[i]
            indices[i] = nearestPaletteIndex(r: Int(px.r), g: Int(px.g), b: Int(px.b), palette: palette)
        }

        var p = 0
        while p < pixelCount {
            let hi = indices[p] & 0x0F
            let lo = (p + 1 < pixelCount) ? (indices[p + 1] & 0x0F) : 0
            raw.append((hi << 4) | lo)
            p += 2
        }

        return zlibCompress(Data(raw))
    }

    /// Bounded, zip-bomb-safe decoder returning a cached `UIImage` suitable for WidgetKit & in-app views.
    public static func decodeUIImage(from compressed: Data) -> UIImage? {
        guard !compressed.isEmpty, compressed.count <= maxCompressedBytes else {
            return nil
        }

        let key = compressed as NSData
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        guard let raw = zlibDecompressBounded(compressed, maxOutputBytes: maxDecompressedBytes) else {
            return nil
        }

        let bytes = [UInt8](raw)
        guard bytes.count >= 49 else { return nil }
        let w = Int(bytes[0])
        let h = Int(bytes[1])
        guard (8...64).contains(w), (8...64).contains(h) else { return nil }

        let pixelCount = w * h
        let packedCount = (pixelCount + 1) / 2
        guard bytes.count == 2 + 45 + packedCount else { return nil }

        var palette = [(r: UInt8, g: UInt8, b: UInt8)](repeating: (0, 0, 0), count: 16)
        for idx in 1...15 {
            let base = 2 + (idx - 1) * 3
            palette[idx] = (bytes[base], bytes[base + 1], bytes[base + 2])
        }

        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        for p in 0..<pixelCount {
            let packedByte = bytes[47 + (p / 2)]
            let palIdx = Int((p % 2 == 0) ? (packedByte >> 4) : (packedByte & 0x0F))
            if palIdx > 0 {
                let c = palette[palIdx]
                let out = p * 4
                rgba[out] = c.r
                rgba[out + 1] = c.g
                rgba[out + 2] = c.b
                rgba[out + 3] = 255
            }
        }

        let cfData = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: cfData),
              let cgImage = CGImage(
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        imageCache.setObject(uiImage, forKey: key)
        return uiImage
    }

    // MARK: - Fast 15-Color Palette Quantizer

    private static func buildPalette15(from pixels: [(r: Int, g: Int, b: Int)]) -> [(r: Int, g: Int, b: Int)] {
        guard !pixels.isEmpty else { return [(255, 255, 255)] }

        // 5-bit per channel histogram (32x32x32 buckets)
        var buckets: [Int: (count: Int, sumR: Int, sumG: Int, sumB: Int)] = [:]
        for px in pixels {
            let key = ((px.r >> 3) << 10) | ((px.g >> 3) << 5) | (px.b >> 3)
            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1
            entry.sumR += px.r
            entry.sumG += px.g
            entry.sumB += px.b
            buckets[key] = entry
        }

        let sorted = buckets.values.sorted { $0.count > $1.count }
        var centers: [(r: Int, g: Int, b: Int)] = []
        centers.reserveCapacity(15)

        // Pass 1: pick distinct color clusters first so eyes/collars/accents stay crisp
        for item in sorted where centers.count < 15 {
            let candidate = (item.sumR / item.count, item.sumG / item.count, item.sumB / item.count)
            let tooClose = centers.contains { c in
                colorDistSq(c, candidate) < 520
            }
            if !tooClose {
                centers.append(candidate)
            }
        }

        // Fill remaining slots with most frequent buckets if needed
        if centers.count < 15 {
            for item in sorted where centers.count < 15 {
                let candidate = (item.sumR / item.count, item.sumG / item.count, item.sumB / item.count)
                if !centers.contains(where: { $0.r == candidate.r && $0.g == candidate.g && $0.b == candidate.b }) {
                    centers.append(candidate)
                }
            }
        }

        guard centers.count > 1 else { return centers }

        // 3 quick k-means refinement iterations
        for _ in 0..<3 {
            var sums = [(r: Int, g: Int, b: Int, count: Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for px in pixels {
                var bestIdx = 0
                var bestDist = Int.max
                for (i, c) in centers.enumerated() {
                    let d = colorDistSq(px, c)
                    if d < bestDist {
                        bestDist = d
                        bestIdx = i
                    }
                }
                sums[bestIdx].r += px.r
                sums[bestIdx].g += px.g
                sums[bestIdx].b += px.b
                sums[bestIdx].count += 1
            }
            for i in 0..<centers.count where sums[i].count > 0 {
                centers[i] = (
                    sums[i].r / sums[i].count,
                    sums[i].g / sums[i].count,
                    sums[i].b / sums[i].count
                )
            }
        }

        return centers
    }

    private static func nearestPaletteIndex(
        r: Int,
        g: Int,
        b: Int,
        palette: [(r: Int, g: Int, b: Int)]
    ) -> UInt8 {
        var bestIdx = 0
        var bestDist = Int.max
        let target = (r: r, g: g, b: b)
        for (i, c) in palette.enumerated() {
            let d = colorDistSq(target, c)
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }
        return UInt8(min(15, bestIdx + 1))
    }

    private static func colorDistSq(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Int {
        let dr = a.r - b.r
        let dg = a.g - b.g
        let db = a.b - b.b
        return dr * dr + dg * dg + db * db
    }

    // MARK: - Bounded Zlib Helpers

    private static func zlibCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let dstCapacity = data.count + 128
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCapacity)
        defer { dst.deallocate() }

        let written = data.withUnsafeBytes { rawBuf -> Int in
            guard let src = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(dst, dstCapacity, src, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: dst, count: written)
    }

    private static func zlibDecompressBounded(_ data: Data, maxOutputBytes: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: maxOutputBytes)
        defer { dst.deallocate() }

        let written = data.withUnsafeBytes { rawBuf -> Int in
            guard let src = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(dst, maxOutputBytes, src, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0, written < maxOutputBytes else { return nil }
        return Data(bytes: dst, count: written)
    }
}
