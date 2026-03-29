import Foundation
import IOKit.ps
import Darwin
// getifaddrs and if_data are available via Darwin (includes <ifaddrs.h> and <net/if.h>)

@MainActor
class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var batteryLevel: Int = -1
    @Published var healthScore: Int = 100
    @Published var topProcesses: [ProcessItem] = []
    @Published var macModel: String = ""
    @Published var chipName: String = ""
    @Published var ramDescription: String = ""
    @Published var macOSVersion: String = ""
    @Published var uptimeSeconds: Int = 0
    // Network throughput — bytes/s since last 2-second tick
    @Published var netBytesInPerSec: Int64 = 0
    @Published var netBytesOutPerSec: Int64 = 0

    private var prevNetIn:  Int64 = 0
    private var prevNetOut: Int64 = 0
    private var netInitialized = false

    private var timer: Timer?
    private var processTask: Task<Void, Never>?
    private var prevUser: UInt32 = 0
    private var prevSys:  UInt32 = 0
    private var prevIdle: UInt32 = 0
    private var prevNice: UInt32 = 0
    private var hasPrev  = false

    func startMonitoring() {
        readStaticInfo()
        updateMetrics()
        fetchProcesses()          // immediate first fetch
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
                self?.fetchProcesses()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        processTask?.cancel()
        processTask = nil
    }

    private func updateMetrics() {
        cpuUsage      = readCPUUsage()
        let mem       = readMemory(); memoryUsed = mem.used; memoryTotal = mem.total
        let dsk       = readDisk();   diskUsed   = dsk.used; diskTotal   = dsk.total
        batteryLevel  = readBattery()
        uptimeSeconds = readUptime()
        updateNetworkThroughput()
        healthScore   = computeHealth()
    }

    // Fetch processes off the main thread using an explicit Task stored as a property
    // so we can cancel it on stopMonitoring. Avoids the Swift 6 actor-isolation
    // problem with Task.detached capturing self.
    private func fetchProcesses() {
        processTask?.cancel()
        processTask = Task {
            let results = await Task.detached(priority: .utility) {
                SystemMonitor.runPS()
            }.value
            // Back on MainActor (Task inherits actor context from @MainActor class)
            guard !Task.isCancelled else { return }
            self.topProcesses = results
        }
    }

    // MARK: CPU
    private func readCPUUsage() -> Double {
        var numCPUs: UInt32 = 0
        var cpuInfo: processor_info_array_t? = nil
        var numCPUInfo: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &numCPUs, &cpuInfo, &numCPUInfo) == KERN_SUCCESS,
              let info = cpuInfo else { return cpuUsage }
        var user: UInt32 = 0, sys: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0
        for i in 0..<Int(numCPUs) {
            let o = i * Int(CPU_STATE_MAX)
            user += UInt32(bitPattern: info[o + Int(CPU_STATE_USER)])
            sys  += UInt32(bitPattern: info[o + Int(CPU_STATE_SYSTEM)])
            idle += UInt32(bitPattern: info[o + Int(CPU_STATE_IDLE)])
            nice += UInt32(bitPattern: info[o + Int(CPU_STATE_NICE)])
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size))
        guard hasPrev else {
            prevUser = user; prevSys = sys; prevIdle = idle; prevNice = nice
            hasPrev = true; return 0
        }
        let dU = user &- prevUser, dS = sys &- prevSys
        let dI = idle &- prevIdle, dN = nice &- prevNice
        prevUser = user; prevSys = sys; prevIdle = idle; prevNice = nice
        // All four terms use &+ so that if any counter wraps (e.g. after weeks of
        // 100% load) the total is still a valid UInt32 rather than a runtime trap.
        let total = Double(dU &+ dS &+ dI &+ dN)
        guard total > 0 else { return cpuUsage }
        return min(100, Double(dU &+ dS &+ dN) / total * 100)
    }

    // MARK: Memory
    private func readMemory() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0; var sz = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &sz, nil, 0)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        return (total - UInt64(stats.free_count) * page - UInt64(stats.inactive_count) * page, total)
    }

    // MARK: Disk
    private func readDisk() -> (used: UInt64, total: UInt64) {
        guard let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        else { return (diskUsed, diskTotal) }
        let t = (a[.systemSize]     as? UInt64) ?? 0
        let f = (a[.systemFreeSize] as? UInt64) ?? 0
        return (t - f, t)
    }

    // MARK: Battery
    private func readBattery() -> Int {
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [AnyObject]
        guard let src  = list.first,
              let info = IOPSGetPowerSourceDescription(snap, src).takeUnretainedValue() as? [String: Any],
              let cap  = info[kIOPSCurrentCapacityKey] as? Int else { return -1 }
        return cap
    }

    // MARK: Processes — reads via sysctl, no subprocess, no pipe deadlock
    nonisolated static func runPS() -> [ProcessItem] {
        // Use `ps` with readDataToEndOfFile BEFORE waitUntilExit to avoid pipe deadlock.
        // The deadlock: ps fills the pipe buffer → blocks writing → waitUntilExit never returns.
        // Fix: read all data first (drains the buffer) → then wait for exit.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-Ao", "pid,pcpu,rss,comm", "-r"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe
        guard (try? proc.run()) != nil else { return [] }

        // CRITICAL: read pipe BEFORE waitUntilExit, otherwise deadlock when buffer fills
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let out = String(data: data, encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n")
            .dropFirst()        // skip header
            .filter { !$0.isEmpty }
            .prefix(5)
            .compactMap { line -> ProcessItem? in
                let p = line.split(separator: " ", maxSplits: 3,
                                   omittingEmptySubsequences: true)
                guard p.count >= 4,
                      let pid = Int(p[0]),
                      let cpu = Double(p[1]),
                      let mem = UInt64(p[2])
                else { return nil }
                // p[3] is full path — grab last component as display name
                let rawName = String(p[3])
                let name    = rawName.components(separatedBy: "/").last
                              .map { $0.isEmpty ? rawName : $0 } ?? rawName
                return ProcessItem(pid: pid, name: name, cpu: cpu,
                                   memoryBytes: mem * 1024)
            }
    }

    // MARK: Network throughput (bytes/s, 2-second delta via getifaddrs)
    // Replaces the useless "Network: —" placeholder card on desktop Macs that have no battery.
    private func updateNetworkThroughput() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(first) }
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            // Only physical interfaces — skip loopback (lo0) and virtual utun/bridge/awdl
            if !name.hasPrefix("lo") && !name.hasPrefix("utun") &&
               !name.hasPrefix("bridge") && !name.hasPrefix("awdl") &&
               !name.hasPrefix("llw") {
                if let data = ifa.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self)
                    totalIn  += Int64(ifData.pointee.ifi_ibytes)
                    totalOut += Int64(ifData.pointee.ifi_obytes)
                }
            }
            cursor = ifa.pointee.ifa_next
        }
        if netInitialized {
            // Timer fires every 2 s — divide delta by interval to get bytes/s
            netBytesInPerSec  = max(0, totalIn  - prevNetIn)  / 2
            netBytesOutPerSec = max(0, totalOut - prevNetOut) / 2
        } else {
            netInitialized = true
        }
        prevNetIn  = totalIn
        prevNetOut = totalOut
    }

    // MARK: Health
    private func computeHealth() -> Int {
        var s = 100
        if cpuUsage > 80 { s -= 20 } else if cpuUsage > 60 { s -= 10 }
        let mp = memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100 : 0
        if mp > 90 { s -= 20 } else if mp > 75 { s -= 10 }
        let dp = diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) * 100 : 0
        if dp > 95 { s -= 20 } else if dp > 85 { s -= 10 }
        if batteryLevel >= 0 && batteryLevel < 20 { s -= 10 }
        return max(0, s)
    }

    // MARK: Static info
    private func readStaticInfo() {
        macOSVersion   = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        macModel       = sysctl("hw.model")
        chipName       = sysctl("machdep.cpu.brand_string")
        let mem        = readMemory()
        ramDescription = "\(mem.total / (1024 * 1024 * 1024)) GB"
    }

    private func readUptime() -> Int {
        var tv = timeval(); var sz = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &tv, &sz, nil, 0)
        return max(0, Int(Date().timeIntervalSince1970) - Int(tv.tv_sec))
    }

    private func sysctl(_ key: String) -> String {
        var sz = 0; sysctlbyname(key, nil, &sz, nil, 0)
        guard sz > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: sz)
        sysctlbyname(key, &buf, &sz, nil, 0)
        // Truncate trailing null bytes then decode as UTF-8.
        // String(decoding:as:) is the recommended replacement for the deprecated
        // String(cString: array) overload that warned about null termination.
        let bytes = buf.prefix(while: { $0 != 0 }).map(UInt8.init)
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct ProcessItem: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let cpu: Double
    let memoryBytes: UInt64
    var memoryString: String { formatBytes(Int64(memoryBytes)) }
}
