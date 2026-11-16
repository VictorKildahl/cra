// front <pid>: activates that app.
import AppKit
let pid = Int32(CommandLine.arguments[1])!
let ok = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) ?? false
usleep(300000)
print(ok, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
