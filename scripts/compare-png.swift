// Compares a component snapshot with its reference (scripts/scenario.sh `snapshot`):
//   xcrun swift scripts/compare-png.swift <reference.png> <new.png> [<diff.png>]
// (scripts/scenario.sh compiles it once per run.)
// Fails when the sizes differ, or when more than 0.05 % of pixels differ by more than 12/255 in
// any channel (anti-aliasing moves a little between machines; geometry and colour do not).
// The diff image shows changed pixels in red over a faded copy of the reference.
import AppKit

func pixels(_ path: String) -> (w: Int, h: Int, data: [UInt8])? {
    guard let file = try? Data(contentsOf: URL(fileURLWithPath: path)), let cg = NSBitmapImageRep(data: file)?.cgImage else { return nil }
    let w = cg.width, h = cg.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, data)
}

let args = CommandLine.arguments
guard args.count >= 3, let a = pixels(args[1]), let b = pixels(args[2]) else {
    print("cannot read \(args.dropFirst().joined(separator: " "))"); exit(2)
}
guard a.w == b.w, a.h == b.h else { print("size \(b.w)x\(b.h), reference \(a.w)x\(a.h)"); exit(1) }
var changed = 0
var diff = [UInt8](repeating: 0, count: a.data.count)
for i in stride(from: 0, to: a.data.count, by: 4) {
    let d = (0..<4).map { abs(Int(a.data[i + $0]) - Int(b.data[i + $0])) }.max()!
    if d > 12 {
        changed += 1
        diff[i] = 255; diff[i + 3] = 255
    } else {
        for k in 0..<3 { diff[i + k] = UInt8(min(255, Int(a.data[i + k]) / 4 + 191)) }
        diff[i + 3] = 255
    }
}
let share = Double(changed) / Double(a.w * a.h)
if args.count > 3, changed > 0,
   let ctx = CGContext(data: &diff, width: a.w, height: a.h, bitsPerComponent: 8, bytesPerRow: a.w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
   let image = ctx.makeImage() {
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[3]))
}
print(String(format: "%d pixels differ (%.3f %%)", changed, share * 100))
exit(share > 0.0005 ? 1 : 0)
