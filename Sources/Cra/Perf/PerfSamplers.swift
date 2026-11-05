import Darwin
import Foundation

/// Cra and its helper processes through libproc: one `proc_pid_rusage` per process, about a
/// millisecond for the lot. Public API, no task ports, works on a notarized hardened build
/// (Chromium's helpers are Cra's children and the same user's processes).
struct PerfProcessSampler {
    /// What each helper is, read once per process (its arguments don't change).
    private var kinds: [pid_t: PerfProcessKind] = [:]

    mutating func read() -> [PerfProcessReading] {
        let me = getpid()
        let pids = [me] + Self.children(of: me)
        kinds = kinds.filter { pids.contains($0.key) }
        return pids.map { pid in
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            } == 0
            let kind: PerfProcessKind
            if let cached = kinds[pid] { kind = cached }
            else {
                let name = pid == me ? "" : Self.name(of: pid)
                let type = pid != me && PerfProcessKind.needsType(name: name) ? Self.chromiumType(of: pid) : nil
                kind = PerfProcessKind.of(name: name, isSelf: pid == me, type: type)
            }
            kinds[pid] = kind
            guard ok else {
                return PerfProcessReading(pid: pid, kind: kind, cpuNs: nil, footprintBytes: nil, diskReadBytes: nil, diskWriteBytes: nil, wakeups: nil)
            }
            return PerfProcessReading(pid: pid, kind: kind, cpuNs: Self.nanoseconds(info.ri_user_time &+ info.ri_system_time),
                                      footprintBytes: Int64(clamping: info.ri_phys_footprint),
                                      diskReadBytes: Int64(clamping: info.ri_diskio_bytesread),
                                      diskWriteBytes: Int64(clamping: info.ri_diskio_byteswritten),
                                      wakeups: Int64(clamping: info.ri_pkg_idle_wkups &+ info.ri_interrupt_wkups))
        }
    }

    /// Chromium starts every helper itself, so they are its children. `proc_listchildpids` is in
    /// the public libproc.h but undocumented; `proc_listpids(PROC_PPID_ONLY)` is the fallback.
    static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 1024)
        let size = Int32(buffer.count * MemoryLayout<pid_t>.size)
        let n = proc_listchildpids(pid, &buffer, size)
        if n > 0 { return Array(buffer.prefix(Int(min(n, Int32(buffer.count))))).filter { $0 > 0 } }
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, size)
        guard bytes > 0 else { return [] }
        return Array(buffer.prefix(Int(bytes) / MemoryLayout<pid_t>.size)).filter { $0 > 0 }
    }

    /// Chromium's `--type=` (renderer, gpu-process, utility) from the process's arguments, which
    /// macOS gives the same user's processes (what `ps` reads).
    static func chromiumType(of pid: pid_t) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        for arg in buffer.prefix(size).split(separator: 0) {
            let s = String(decoding: arg, as: UTF8.self)
            if s.hasPrefix("--type=") { return String(s.dropFirst(7)) }
        }
        return nil
    }

    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    /// rusage times are mach ticks (125/3 ns each on Apple silicon).
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(max(tb.numer, 1)), UInt64(max(tb.denom, 1)))
    }()

    static func nanoseconds(_ ticks: UInt64) -> UInt64 { ticks.multipliedReportingOverflow(by: timebase.numer).partialValue / timebase.denom }
}

/// The Mac as a whole: CPU over the last interval, memory pressure, heat, Low Power Mode, free disk.
struct PerfSystemSampler {
    private var previousTicks: [UInt64]?
    private var freeDisk: (bytes: Int64?, at: UInt64) = (nil, 0)

    mutating func read(dataFolder: URL) -> PerfSystemSample {
        let now = Perf.now()
        // The volume's free space changes slowly and costs a file-system call: once a minute.
        if freeDisk.at == 0 || now &- freeDisk.at > 60_000_000_000 {
            // Foundation's "important usage" capacity asks storage policy about reclaimable
            // space (6–18 ms CPU here). The recorder needs free space, not a purge estimate.
            // statfs reads the volume's available blocks directly, in a few microseconds.
            freeDisk = (Self.availableDisk(dataFolder), now)
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return PerfSystemSample(cpuPct: cpu(), memoryPressure: PerfSystemSample.pressure(level: Self.pressureLevel()),
                                thermalState: thermal, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                freeDiskBytes: freeDisk.bytes)
    }

    static func availableDisk(_ folder: URL) -> Int64? {
        var info = statfs()
        guard statfs(folder.path, &info) == 0, info.f_bsize > 0 else { return nil }
        let bytes = info.f_bavail.multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !bytes.overflow else { return nil }
        return Int64(clamping: bytes.partialValue)
    }

    /// All cores' user, system, idle and nice ticks since boot; busy share since the last call.
    private mutating func cpu() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let ticks = [UInt64(t.0), UInt64(t.1), UInt64(t.2), UInt64(t.3)]   // user, system, idle, nice
        defer { previousTicks = ticks }
        guard let p = previousTicks else { return nil }
        let d = zip(ticks, p).map { $0 >= $1 ? $0 - $1 : 0 }
        let total = d.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - d[2]) / Double(total) * 100
    }

    static func pressureLevel() -> Int32? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 ? level : nil
    }
}

enum PerfFolderSizes {
    /// Chromium's caches inside a profile: they grow and shrink by themselves.
    static let cacheFolders: Set<String> = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache"]

    /// The Chromium folder's size without its caches, and the caches. Walks every file: only at
    /// export and when the Performance pane asks, never on a timer.
    static func measure(_ chromium: URL) -> (profile: Int64, cache: Int64) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let walk = FileManager.default.enumerator(at: chromium, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return (0, 0) }
        var profile: Int64 = 0, cache: Int64 = 0
        for case let url as URL in walk {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? 0)
            let relative = url.path.dropFirst(chromium.path.count).split(separator: "/")
            if relative.contains(where: { cacheFolders.contains(String($0)) }) { cache += size } else { profile += size }
        }
        return (profile, cache)
    }
}
