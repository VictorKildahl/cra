// axset <pid> <text> [timeout-s]: waits for the app's focused UI element to be a text field, sets its value and checks it
// stayed. Prints its role/identifier.
import ApplicationServices; import Foundation
let pid = Int32(CommandLine.arguments[1])!, text = CommandLine.arguments[2]
let timeout = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 3
let app = AXUIElementCreateApplication(pid)
let start = Date()
while Date().timeIntervalSince(start) < timeout {
  var f: CFTypeRef?
  if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success, let el = f {
    let e = el as! AXUIElement
    var role: CFTypeRef?; AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role)
    var ident: CFTypeRef?; AXUIElementCopyAttributeValue(e, "AXIdentifier" as CFString, &ident)
    let r = role as? String ?? ""
    if r == "AXTextField" || r == "AXTextArea" || r == "AXComboBox" {
      let st = AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, text as CFString)
      // Focus can still be moving (a command bar opening takes it from the field under it): check that the
      // field focused 150 ms later holds the text, and set it again if not.
      usleep(150000)
      var f2: CFTypeRef?, v: CFTypeRef?
      if st == .success, AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f2) == .success,
         let el2 = f2, AXUIElementCopyAttributeValue(el2 as! AXUIElement, kAXValueAttribute as CFString, &v) == .success,
         (v as? String) == text {
        print(r, ident as? String ?? "-", st.rawValue); exit(0)
      }
    }
  }
  usleep(20000)
}
print("no text field focused"); exit(1)
