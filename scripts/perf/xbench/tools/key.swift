// key <spec>...: posts keyboard events at the HID level and prints the epoch ms just before the last one.
// spec: "cmd+t", "ctrl+tab", "return", "text:<string>", "sleep:<ms>"
import CoreGraphics; import Foundation
let codes: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46,"tab":48,"space":49,"return":36,"escape":53,"left":123,"right":124,"down":125,"up":126,"delete":51]
let src = CGEventSource(stateID: .hidSystemState)
var last = 0.0
// Modifiers go down and up as keys of their own around the key, as a keyboard sends them (an Arc-style
// tab switcher commits on the Control key's release).
let modifierKeys: [(CGEventFlags, CGKeyCode)] = [(.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59)]
func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
  var held: CGEventFlags = []
  for (flag, key) in modifierKeys where flags.contains(flag) {
    held.insert(flag)
    let m = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)!; m.type = .flagsChanged; m.flags = held
    m.post(tap: .cghidEventTap); usleep(4000)
  }
  let d = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!; d.flags = flags
  let u = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!; u.flags = flags
  last = Date().timeIntervalSince1970 * 1000
  d.post(tap: .cghidEventTap); usleep(8000); u.post(tap: .cghidEventTap); usleep(4000)
  for (flag, key) in modifierKeys.reversed() where flags.contains(flag) {
    held.remove(flag)
    let m = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)!; m.type = .flagsChanged; m.flags = held
    m.post(tap: .cghidEventTap); usleep(4000)
  }
}
for spec in CommandLine.arguments.dropFirst() {
  if spec.hasPrefix("sleep:") { usleep(UInt32(Int(spec.dropFirst(6))! * 1000)); continue }
  if spec.hasPrefix("text:") {
    for ch in spec.dropFirst(5) {
      let s = Array(String(ch).utf16)
      let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)!; d.keyboardSetUnicodeString(stringLength: s.count, unicodeString: s)
      let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)!; u.keyboardSetUnicodeString(stringLength: s.count, unicodeString: s)
      d.post(tap: .cghidEventTap); usleep(3000); u.post(tap: .cghidEventTap); usleep(3000)
    }
    continue
  }
  var flags: CGEventFlags = []; var key = ""
  for part in spec.split(separator: "+") {
    switch part { case "cmd": flags.insert(.maskCommand); case "ctrl": flags.insert(.maskControl); case "alt": flags.insert(.maskAlternate); case "shift": flags.insert(.maskShift); default: key = String(part) }
  }
  post(codes[key]!, flags)
}
print(String(format: "%.1f", last))
