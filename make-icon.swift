import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSColor(red: 0.09, green: 0.09, blue: 0.13, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.20, green: 0.18, blue: 0.30, alpha: 1),
               ending: NSColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: squircle, angle: -90)

    let coral = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    let tabColors = [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0.18)]
    for (i, color) in tabColors.enumerated() {
        let x = 224 + CGFloat(i) * 196
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 640, width: 180, height: 110), xRadius: 30, yRadius: 30).fill()
    }
    let front = NSRect(x: 200, y: 230, width: 624, height: 460)
    coral.setFill()
    NSBezierPath(roundedRect: NSRect(x: 616, y: 640, width: 180, height: 110), xRadius: 30, yRadius: 30).fill()
    NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1).setFill()
    let window = NSBezierPath(roundedRect: front, xRadius: 44, yRadius: 44)
    window.fill()
    coral.setStroke()
    window.lineWidth = 14
    window.stroke()

    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 290, y: 560))
    prompt.line(to: NSPoint(x: 400, y: 470))
    prompt.line(to: NSPoint(x: 290, y: 380))
    prompt.lineWidth = 46
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    coral.setStroke()
    prompt.stroke()
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 450, y: 360, width: 170, height: 44), xRadius: 22, yRadius: 22).fill()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
