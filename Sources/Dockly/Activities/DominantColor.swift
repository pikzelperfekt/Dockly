import AppKit

// Extracts a vivid, representative accent color from artwork — used to make the
// pill glow in the colors of whatever's playing (Dynamic Island style).
enum DominantColor {
    private static var cache: [Int: NSColor] = [:]
    private static var paletteCache: [Int: [NSColor]] = [:]

    /// Up to `count` vivid, hue-separated colors from the artwork, ordered by
    /// prominence. Used for the animated multi-color border.
    static func palette(_ data: Data, count: Int = 4) -> [NSColor] {
        let key = data.hashValue
        if let p = paletteCache[key] { return p }
        guard let img = NSImage(data: data),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return [] }
        let w = 32, h = 32
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let px = ctx.data else { return [] }
        let buf = px.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Accumulate vivid pixels into 12 hue buckets (weighted r/g/b + weight).
        let buckets = 12
        var accR = [Double](repeating: 0, count: buckets)
        var accG = [Double](repeating: 0, count: buckets)
        var accB = [Double](repeating: 0, count: buckets)
        var accW = [Double](repeating: 0, count: buckets)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(buf[i])/255, g = Double(buf[i+1])/255, b = Double(buf[i+2])/255
            let mx = max(r,g,b), mn = min(r,g,b)
            let sat = mx == 0 ? 0 : (mx-mn)/mx
            guard mx > 0.15, mx < 0.99, sat > 0.2 else { continue }
            let nsc = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var hue: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            nsc.getHue(&hue, saturation: &s, brightness: &v, alpha: &a)
            let bkt = min(buckets - 1, Int(hue * CGFloat(buckets)))
            let weight = sat * sat * mx
            accR[bkt] += r*weight; accG[bkt] += g*weight; accB[bkt] += b*weight; accW[bkt] += weight
        }
        let ranked = (0..<buckets)
            .filter { accW[$0] > 0 }
            .sorted { accW[$0] > accW[$1] }
            .prefix(count)
            .map { i in boost(NSColor(srgbRed: accR[i]/accW[i], green: accG[i]/accW[i], blue: accB[i]/accW[i], alpha: 1)) }
        let result = Array(ranked)
        if paletteCache.count > 50 { paletteCache.removeAll() }
        paletteCache[key] = result
        return result
    }

    static func from(_ data: Data) -> NSColor? {
        let key = data.hashValue
        if let c = cache[key] { return c }
        guard let img = NSImage(data: data),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        // Downscale to a small grid for speed.
        let w = 24, h = 24
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = rep.cgImage else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let px = ctx.data else { return nil }
        let buf = px.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Pick the pixel cluster with the best saturation × brightness score,
        // averaging similar vivid pixels so we get a stable, punchy color.
        var rSum = 0.0, gSum = 0.0, bSum = 0.0, wSum = 0.0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(buf[i]) / 255, g = Double(buf[i+1]) / 255, b = Double(buf[i+2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx == 0 ? 0 : (mx - mn) / mx
            let bri = mx
            // Weight vivid, mid-bright pixels; ignore near-black/near-white/gray.
            guard bri > 0.15, bri < 0.98, sat > 0.18 else { continue }
            let weight = sat * sat * bri
            rSum += r * weight; gSum += g * weight; bSum += b * weight; wSum += weight
        }
        let color: NSColor
        if wSum > 0 {
            color = NSColor(srgbRed: rSum/wSum, green: gSum/wSum, blue: bSum/wSum, alpha: 1)
        } else {
            // Fallback: plain average (covers grayscale art).
            var r = 0.0, g = 0.0, b = 0.0
            let n = Double(w * h)
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                r += Double(buf[i]); g += Double(buf[i+1]); b += Double(buf[i+2])
            }
            color = NSColor(srgbRed: r/n/255, green: g/n/255, blue: b/n/255, alpha: 1)
        }
        // Boost so it reads as an accent even from muted covers.
        let vivid = boost(color)
        if cache.count > 50 { cache.removeAll() }
        cache[key] = vivid
        return vivid
    }

    private static func boost(_ c: NSColor) -> NSColor {
        guard let s = c.usingColorSpace(.sRGB) else { return c }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        s.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        return NSColor(hue: hue,
                       saturation: min(1, sat * 1.3 + 0.1),
                       brightness: min(1, max(bri, 0.6)),
                       alpha: 1)
    }
}
