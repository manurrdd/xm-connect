import AppKit

// Draws the app icon and writes Resources/AppIcon.icns. Run with: swift Tools/make-icon.swift
// The mark is drawn here rather than taken from SF Symbols, whose licence excludes app icons.

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let context = NSGraphicsContext.current!.cgContext
    let scale = size / 1024

    context.saveGState()
    let plate = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 40 * scale, dy: 40 * scale)
    let plateShape = CGPath(
        roundedRect: plate, cornerWidth: 200 * scale, cornerHeight: 200 * scale, transform: nil
    )
    context.addPath(plateShape)
    context.clip()
    context.drawLinearGradient(
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 0.16, green: 0.19, blue: 0.27, alpha: 1),
                CGColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        )!,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    context.restoreGState()

    let band = CGMutablePath()
    band.addArc(
        center: CGPoint(x: 512 * scale, y: 470 * scale),
        radius: 250 * scale,
        startAngle: 0,
        endAngle: .pi,
        clockwise: false
    )
    context.addPath(band)
    context.setStrokeColor(CGColor(red: 0.42, green: 0.68, blue: 1, alpha: 1))
    context.setLineWidth(74 * scale)
    context.setLineCap(.round)
    context.strokePath()

    context.setFillColor(CGColor(red: 0.91, green: 0.95, blue: 1, alpha: 1))
    for x in [262.0, 762.0] {
        let cup = CGRect(
            x: (x - 78) * scale, y: 250 * scale, width: 156 * scale, height: 285 * scale
        )
        context.addPath(CGPath(
            roundedRect: cup, cornerWidth: 78 * scale, cornerHeight: 78 * scale, transform: nil
        ))
    }
    context.fillPath()

    return image
}

let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (point, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = CGFloat(point * scale)
        let image = draw(size: pixels)
        guard let data = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        else { fatalError("could not render \(point)@\(scale)x") }

        let suffix = scale == 1 ? "" : "@2x"
        try! png.write(to: iconset.appendingPathComponent("icon_\(point)x\(point)\(suffix).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
