import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Composes App Store header artwork from one iPad 13" portrait capture (2064 x 2752) of the
// faceplate: the reel on the left, the display and tape scale in the art safe area, the mixer
// on the right. Every part is the real control, cut from the capture; only the spacing is new.
//
// compose.swift out W H safeX safeY safeW safeH capture.png      (safe area from the top left)
let a = CommandLine.arguments
let n = a[2...7].map { CGFloat(Double($0)!) }
let W = n[0], H = n[1], safe = CGRect(x: n[2], y: n[3], width: n[4], height: n[5])
let src = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: a[8]) as CFURL, nil)!, 0, nil)!
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.interpolationQuality = .high

// The faceplate colour, read from the capture's edge, fills the sheet.
let edge = src.cropping(to: CGRect(x: 4, y: 1400, width: 1, height: 1))!
c.draw(edge, in: CGRect(x: 0, y: 0, width: W, height: H))

/// Draws a part of the capture (top-left coordinates) with its top-left corner at `at`.
func place(_ part: CGRect, at p: CGPoint, scale s: CGFloat) {
    let piece = src.cropping(to: part)!
    let r = CGRect(x: p.x, y: H - p.y - part.height * s, width: part.width * s, height: part.height * s)
    c.saveGState()
    c.clip(to: r.insetBy(dx: 3, dy: 3))      // the resampled edge would show as a hairline
    c.draw(piece, in: r)
    c.restoreGState()
}

let display = CGRect(x: 80, y: 176, width: 1259, height: 304)
let centre = CGRect(x: 56, y: 150, width: 1308, height: 546)          // display and tape scale
let reel = CGRect(x: 54, y: 1029, width: 1310, height: 1310)
let mixerX: CGFloat = 1352, mixerW: CGFloat = 656

// Centre: the display spans the safe area's width; display and scale sit in its middle.
// Where the sheet leaves room below, the wheels and keys follow as they do on the faceplate.
// A wide safe area is not filled: the display never takes more than 43% of the sheet.
let shown = min(safe.width, W * 0.43), left = safe.midX - shown / 2, right = safe.midX + shown / 2
let cs = shown / display.width
let centreX = left - (display.minX - centre.minX) * cs
let centreY = safe.midY - centre.height * cs / 2
place(centre, at: CGPoint(x: centreX, y: centreY), scale: cs)
let controls = CGRect(x: centre.minX, y: centre.maxY, width: centre.width, height: 244)
if H - (centreY + centre.height * cs) > controls.height * cs * 2.2 {
    place(controls, at: CGPoint(x: centreX, y: centreY + centre.height * cs), scale: cs)
}

// Left: the reel, as tall as the sheet allows, running off the edge.
let gap = shown * 0.06
let rs = min(H * 0.86, (left - gap) * 1.75) / reel.width
place(reel, at: CGPoint(x: left - gap - reel.width * rs, y: H / 2 - reel.height * rs / 2), scale: rs)

// Right: the mixer. Whole strips (pan, fader, mute) where they fit; otherwise the faders alone.
let whole = H / 2100 >= 1
let ms = whole ? H / 2100 : H / 1300
let strip = whole ? CGRect(x: mixerX, y: 490, width: mixerW, height: 1810)
                  : CGRect(x: mixerX, y: 870, width: mixerW, height: 1070)
place(strip, at: CGPoint(x: right + gap * 1.6, y: (H - strip.height * ms) / 2), scale: ms)

let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
