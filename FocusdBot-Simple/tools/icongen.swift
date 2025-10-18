import AppKit

// Simple programmatic robot icon renderer
// Usage: icongen [outputPath]

func drawRobotIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(NSColor.clear.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Squircle background
    let bgRect = CGRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.28, alpha: 1).setFill()
    bgPath.fill()

    // Robot head
    let headRect = CGRect(x: size * 0.24, y: size * 0.50, width: size * 0.52, height: size * 0.30)
    let headPath = NSBezierPath(roundedRect: headRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
    headPath.fill()

    // Antennas
    let antennaStemWidth = size * 0.012
    let antennaStemHeight = size * 0.05
    let leftStem = CGRect(x: headRect.minX + size * 0.06, y: headRect.maxY - size * 0.015, width: antennaStemWidth, height: antennaStemHeight)
    let rightStem = CGRect(x: headRect.maxX - size * 0.072, y: headRect.maxY - size * 0.015, width: antennaStemWidth, height: antennaStemHeight)
    NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
    ctx.fill(leftStem)
    ctx.fill(rightStem)
    let bulbRadius = size * 0.014
    let leftBulb = NSBezierPath(ovalIn: CGRect(x: leftStem.midX - bulbRadius, y: leftStem.maxY, width: bulbRadius * 2, height: bulbRadius * 2))
    let rightBulb = NSBezierPath(ovalIn: CGRect(x: rightStem.midX - bulbRadius, y: rightStem.maxY, width: bulbRadius * 2, height: bulbRadius * 2))
    NSColor.systemYellow.setFill()
    leftBulb.fill(); rightBulb.fill()

    // Angry brows (closed eyes) – closer and lower
    let browWidth = size * 0.13
    let browHeight = size * 0.02
    let browY = headRect.midY - size * 0.01
    let gap = size * 0.012
    let leftBrowRect = CGRect(x: headRect.midX - gap - browWidth, y: browY, width: browWidth, height: browHeight)
    let rightBrowRect = CGRect(x: headRect.midX + gap, y: browY, width: browWidth, height: browHeight)
    let browPathL = NSBezierPath(roundedRect: leftBrowRect, xRadius: browHeight/2, yRadius: browHeight/2)
    let browPathR = NSBezierPath(roundedRect: rightBrowRect, xRadius: browHeight/2, yRadius: browHeight/2)
    NSColor.black.setFill()
    NSGraphicsContext.saveGraphicsState()
    var lTransform = AffineTransform(translationByX: leftBrowRect.minX, byY: leftBrowRect.minY)
    lTransform.rotate(byDegrees: 28)
    lTransform.translate(x: -leftBrowRect.minX, y: -leftBrowRect.minY)
    browPathL.transform(using: lTransform)
    browPathL.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    var rTransform = AffineTransform(translationByX: rightBrowRect.minX, byY: rightBrowRect.minY)
    rTransform.rotate(byDegrees: -28)
    rTransform.translate(x: -rightBrowRect.minX, y: -rightBrowRect.minY)
    browPathR.transform(using: rTransform)
    browPathR.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Body panel – centered below head
    let bodyRect = CGRect(x: size * 0.30, y: size * 0.22, width: size * 0.40, height: size * 0.18)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
    bodyPath.fill()

    // Neon mouth line
    let timerRect = CGRect(x: bodyRect.minX + size * 0.05, y: bodyRect.midY - size * 0.007, width: bodyRect.width - size * 0.10, height: size * 0.014)
    NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.5, alpha: 1).setFill()
    NSBezierPath(roundedRect: timerRect, xRadius: size * 0.01, yRadius: size * 0.01).fill()

    return image
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let image = drawRobotIcon(size: 1024)
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to render PNG\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote icon to \(outPath)")
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}


