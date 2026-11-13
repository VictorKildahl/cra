// fp <pid> [--self]: physical footprint (MB), CPU time (ns) and wakeups summed over the pid's process tree
// (--self: that process alone), with the same per process kind, as one JSON line. Built by bench.sh.
import Darwin
import Foundation
func children(_ p: pid_t) -> [pid_t] {
    var buf = [pid_t](repeating: 0, count: 4096)
    let n = proc_listchildpids(p, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
    return n > 0 ? Array(buf.prefix(Int(n))) : []
}
let root = pid_t(CommandLine.arguments[1])!
var all = [root]; var i = 0
if !CommandLine.arguments.contains("--self") { while i < all.count { all += children(all[i]); i += 1 } }
var fp: UInt64 = 0, cpu: UInt64 = 0, wk: UInt64 = 0
var kinds: [String: UInt64] = [:]
var kcpu: [String: UInt64] = [:], kwk: [String: UInt64] = [:]
for p in all {
    var ri = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(p, RUSAGE_INFO_V4, $0) } }
    guard r == 0 else { continue }
    fp += ri.ri_phys_footprint; cpu += ri.ri_user_time + ri.ri_system_time; wk += ri.ri_pkg_idle_wkups + ri.ri_interrupt_wkups
    var path = [CChar](repeating: 0, count: 4096); proc_pidpath(p, &path, 4096)
    let n = String(cString: path)
    let k = n.contains("(Renderer)") ? "renderer" : n.contains("(GPU)") ? "gpu" : n.contains("(Plugin)") ? "plugin" : n.hasSuffix("MacOS/Cra") ? "browser" : n.contains("Cra Helper.app") ? "utility" : "other:" + (n.split(separator: "/").last.map(String.init) ?? "?")
    kinds[k, default: 0] += ri.ri_phys_footprint
    kcpu[k, default: 0] += ri.ri_user_time + ri.ri_system_time
    kwk[k, default: 0] += ri.ri_pkg_idle_wkups + ri.ri_interrupt_wkups
}
var tb = mach_timebase_info(); mach_timebase_info(&tb)
let out: [String: Any] = ["procs": all.count, "fpMB": Double(fp) / 1048576, "cpuNs": Double(cpu) * Double(tb.numer) / Double(tb.denom), "wakeups": wk,
  "kindsMB": kinds.mapValues { Double($0) / 1048576 }, "kindsCpuNs": kcpu.mapValues { Double($0) * Double(tb.numer) / Double(tb.denom) }, "kindsWk": kwk]
print(String(data: try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]), encoding: .utf8)!)
