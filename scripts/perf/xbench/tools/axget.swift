// axget <pid>: the value of the app's focused UI element (empty if none).
import ApplicationServices; import Foundation
let app = AXUIElementCreateApplication(Int32(CommandLine.arguments[1])!)
var f: CFTypeRef?, v: CFTypeRef?
if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success, let el = f,
   AXUIElementCopyAttributeValue(el as! AXUIElement, kAXValueAttribute as CFString, &v) == .success, let s = v as? String {
  print(s)
}
