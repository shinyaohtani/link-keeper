import AppKit

/// ファビコン画像データを 32x32 にリサイズする値型。
struct FaviconImage {
    let rawData: Data

    var resized: Data? {
        guard let image = NSImage(data: rawData) else { return nil }
        let size = NSSize(width: 32, height: 32)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return rawData }
        return png
    }
}
