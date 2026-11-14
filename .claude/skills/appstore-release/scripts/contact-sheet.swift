// contact-sheet.swift out.png image [image …] — numbered two-column sheet for choosing between images.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
let a = Array(CommandLine.arguments.dropFirst())
let imgs = a.dropFirst().map { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: $0) as CFURL, nil)!, 0, nil)! }
let w: CGFloat = 1200, h: CGFloat = w * CGFloat(imgs[0].height) / CGFloat(imgs[0].width), pad: CGFloat = 24, label: CGFloat = 56
let rows = CGFloat((imgs.count + 1) / 2)
let W = 2 * w + 3 * pad, H = rows * (h + label) + pad
let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(gray: 0.96, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
c.interpolationQuality = .high
for (i, im) in imgs.enumerated() {
    let col = CGFloat(i % 2), row = CGFloat(i / 2)
    let x = pad + col * (w + pad), top = row * (h + label) + label
    c.draw(im, in: CGRect(x: x, y: H - top - h, width: w, height: h))
    let s = NSAttributedString(string: "\(i + 1)", attributes: [kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica-Bold" as CFString, 32, nil), kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.1, alpha: 1)])
    c.textPosition = CGPoint(x: x, y: H - top + 12); CTLineDraw(CTLineCreateWithAttributedString(s), c)
}
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[0]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
