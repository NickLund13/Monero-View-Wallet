// Not the app: the iOS build workflow (.github/workflows/ios-build.yml) runs
// this on the Mac with `xcrun swift tool/snapshot_colors.swift <image>` to
// check the app switcher's snapshot of the app, which iOS saves as the app
// goes to the background. The app covers itself before that, so the snapshot
// must be one flat color: none of the screen behind may show.
//
// Prints the image's size, its commonest color and how much of it that color
// covers.
// Exits 0 when that is at least 97% (the status bar may draw on it), 3 when
// it is less, and 2 when the image can't be read.

import CoreGraphics
import Foundation
import ImageIO

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  print("can't read \(url.lastPathComponent)")
  exit(2)
}
let width = image.width
let height = image.height
var pixels = [UInt32](repeating: 0, count: width * height)
let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
  guard
    let context = CGContext(
      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return false }
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  return true
}
guard drawn, !pixels.isEmpty else {
  print("can't draw \(url.lastPathComponent)")
  exit(2)
}
var counts: [UInt32: Int] = [:]
for pixel in pixels { counts[pixel, default: 0] += 1 }
let (color, commonest) = counts.max { $0.value < $1.value }!
let percent = commonest * 100 / pixels.count
// A pixel's bytes are red, green, blue and alpha, read as a little-endian
// number.
let hex = String(
  format: "#%02X%02X%02X", color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF)
print(
  "\(url.lastPathComponent): \(width)x\(height), \(counts.count) colors, the commonest (\(hex)) on \(percent)%"
)
exit(percent >= 97 ? 0 : 3)
