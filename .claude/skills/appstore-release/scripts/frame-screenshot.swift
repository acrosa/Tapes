import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Frames an App Store screenshot: a caption at the top left, the capture below in a plain device
// outline, on the capture's own background colour. With three captures, fans them out.
//
// frame-screenshot.swift out W H "caption|second line" ink font image [image image]
//   W H    the slot's exact size, e.g. 1206 2622 (iPhone) or 2064 2752 (iPad 13")
//   ink    "dark" for dark text on a light background, "light" for the reverse
//   font   path to an .otf/.ttf, or "-" for the system's Helvetica Neue Medium
let a = Array(CommandLine.arguments.dropFirst())
let out = a[0], W = CGFloat(Double(a[1])!), H = CGFloat(Double(a[2])!)
let lines = a[3].split(separator: "|").map(String.init)
let darkInk = a[4] == "dark"
let fontURL = URL(fileURLWithPath: a[5])
let images = a.dropFirst(6).map { p -> CGImage in
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, 0, nil)!
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Background: the faceplate colour of the first screenshot, read from its edge.
func edgeColour(_ i: CGImage) -> CGColor {
    let p = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    p.draw(i, in: CGRect(x: -6, y: -CGFloat(i.height) / 2, width: CGFloat(i.width), height: CGFloat(i.height)))
    let d = p.data!.assumingMemoryBound(to: UInt8.self)
    return CGColor(srgbRed: CGFloat(d[0]) / 255, green: CGFloat(d[1]) / 255, blue: CGFloat(d[2]) / 255, alpha: 1)
}
c.setFillColor(edgeColour(images[0])); c.fill(CGRect(x: 0, y: 0, width: W, height: H))

let u = W / 165            // 8px on the phone canvas; everything below is whole units of it
let margin = 12 * u
let ink = darkInk ? CGColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1)
                  : CGColor(srgbRed: 0.93, green: 0.92, blue: 0.90, alpha: 1)

// Caption, top left, on the margin.
let size = 13 * u, leading = 15 * u
let font: CTFont
if FileManager.default.fileExists(atPath: fontURL.path),
   let desc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first {
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    font = CTFontCreateWithFontDescriptor(desc, size, nil)
} else {
    font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
}
var y = H - 14 * u - size
for l in lines {
    let s = NSAttributedString(string: l, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: ink,
        kCTKernAttributeName as NSAttributedString.Key: -0.03 * size])
    c.textPosition = CGPoint(x: margin, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(s), c)
    y -= leading
}
let captionBottom = H - 14 * u - leading * CGFloat(lines.count) - 6 * u

func device(_ i: CGImage, in r: CGRect) {
    let bezel = r.width * (r.width / r.height > 0.6 ? 0.016 : 0.022), radius = r.width * (r.width / r.height > 0.6 ? 0.045 : 0.115)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -3 * u), blur: 8 * u, color: CGColor(gray: 0, alpha: 0.28))
    let body = r.insetBy(dx: -bezel, dy: -bezel)
    c.addPath(CGPath(roundedRect: body, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
    c.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.clip()
    c.interpolationQuality = .high
    c.draw(i, in: r)
    c.restoreGState()
}
func fit(_ i: CGImage, width: CGFloat) -> CGSize { CGSize(width: width, height: width * CGFloat(i.height) / CGFloat(i.width)) }

let floor = 10 * u
if images.count == 1 {
    let i = images[0]
    var s = fit(i, width: W - 2 * margin - 8 * u)
    let room = captionBottom - floor
    if s.height > room { s = CGSize(width: room * s.width / s.height, height: room) }
    device(i, in: CGRect(x: (W - s.width) / 2, y: floor + (room - s.height) / 2, width: s.width, height: s.height))
} else {
    // Three finishes: two behind, one in front.
    let room = captionBottom - floor
    var front = fit(images[1], width: W * 0.62)
    if front.height > room { front = CGSize(width: room * front.width / front.height, height: room) }
    let back = CGSize(width: front.width * 0.86, height: front.height * 0.86)
    let mid = floor + (room - front.height) / 2
    let shift = (W - 2 * margin - back.width) / 2
    device(images[0], in: CGRect(x: W / 2 - shift - back.width / 2, y: mid + (front.height - back.height) / 2, width: back.width, height: back.height))
    device(images[2], in: CGRect(x: W / 2 + shift - back.width / 2, y: mid + (front.height - back.height) / 2, width: back.width, height: back.height))
    device(images[1], in: CGRect(x: (W - front.width) / 2, y: mid, width: front.width, height: front.height))
}
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
