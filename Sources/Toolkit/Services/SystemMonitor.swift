import Combine
import Foundation

struct CPUInfo {
    var overall: Double = 0
    var perCore: [Double] = []
}

struct MemoryInfo {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var appMemory: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
}

struct NetworkInfo {
    var inRate: Double = 0
    var outRate: Double = 0
}

struct DiskInfo {
    var total: UInt64 = 0
    var free: UInt64 = 0
}

final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu = CPUInfo()
    @Published private(set) var memory = MemoryInfo()
    @Published private(set) var network = NetworkInfo()
    @Published private(set) var disk = DiskInfo()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var netInHistory: [Double] = []
    @Published private(set) var netOutHistory: [Double] = []
    @Published private(set) var statusText = "--% --"
    @Published private(set) var bootDate = Date()

    private var timer: Timer?
    private var prevTotal: [UInt64]?
    private var prevIdle: [UInt64]?
    private var lastNet: (inBytes: UInt64, outBytes: UInt64)?
    private var lastTick: Date?
    private var sampleCount = 0

    var uptime: TimeInterval {
        max(Date().timeIntervalSince(bootDate), 0)
    }

    func start(interval: TimeInterval = 1) {
        bootDate = Self.readBootDate()
        memory.total = Self.readTotalMemory()
        disk = Self.readDisk()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    private func sample() {
        sampleCount += 1
        let now = Date()
        let elapsed = lastTick.map { max(now.timeIntervalSince($0), 0.05) }
        lastTick = now

        sampleCPU()
        sampleMemory()
        sampleNetwork(elapsed: elapsed)
        if sampleCount % 30 == 1 {
            disk = Self.readDisk()
        }

        cpuHistory.append(cpu.overall)
        netInHistory.append(network.inRate)
        netOutHistory.append(network.outRate)
        if cpuHistory.count > 90 { cpuHistory.removeFirst(cpuHistory.count - 90) }
        if netInHistory.count > 90 { netInHistory.removeFirst(netInHistory.count - 90) }
        if netOutHistory.count > 90 { netOutHistory.removeFirst(netOutHistory.count - 90) }

        statusText = "\(Int(cpu.overall.rounded()))% \(Format.bytesShort(memory.used))"
    }

    private func sampleCPU() {
        var coreCount: natural_t = 0
        var infoPointer: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &coreCount,
            &infoPointer,
            &infoCount
        )
        guard kr == KERN_SUCCESS, let pointer = infoPointer, coreCount > 0 else { return }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: pointer)), size)
        }

        let states = Int(CPU_STATE_MAX)
        var perCore: [Double] = []
        var totals: [UInt64] = []
        var idles: [UInt64] = []

        for core in 0..<Int(coreCount) {
            let base = core * states
            let user = UInt64(pointer[base + Int(CPU_STATE_USER)])
            let system = UInt64(pointer[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(pointer[base + Int(CPU_STATE_IDLE)])
            let nice = UInt64(pointer[base + Int(CPU_STATE_NICE)])
            let total = user + system + idle + nice
            totals.append(total)
            idles.append(idle)

            var usage = 0.0
            if let prevT = prevTotal, let prevI = prevIdle,
               core < prevT.count, core < prevI.count,
               total > prevT[core], idle >= prevI[core] {
                let totalDelta = Double(total - prevT[core])
                let idleDelta = Double(idle - prevI[core])
                usage = (totalDelta - idleDelta) / totalDelta * 100
            }
            perCore.append(min(max(usage, 0), 100))
        }

        prevTotal = totals
        prevIdle = idles
        let overall = perCore.reduce(0, +) / Double(max(perCore.count, 1))
        cpu = CPUInfo(overall: overall, perCore: perCore)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, host_info64_t($0), &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        var pageSize = vm_size_t(0)
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let free = UInt64(stats.free_count) * page

        var info = MemoryInfo()
        info.total = memory.total
        info.used = active + wired + compressed
        info.appMemory = active + wired - min(purgeable, active + wired)
        info.wired = wired
        info.compressed = compressed
        info.cached = inactive + purgeable + speculative
        info.free = free + speculative
        (info.swapUsed, info.swapTotal) = Self.readSwap()
        memory = info
    }

    private func sampleNetwork(elapsed: TimeInterval?) {
        let counters = Self.interfaceCounters()
        var info = NetworkInfo()
        if let elapsed, let last = lastNet {
            info.inRate = max(Double(counters.inBytes) - Double(last.inBytes), 0) / elapsed
            info.outRate = max(Double(counters.outBytes) - Double(last.outBytes), 0) / elapsed
        }
        lastNet = counters
        network = info
    }

    private static func readTotalMemory() -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }

    private static func readSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    private static func readBootDate() -> Date {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return Date() }
        return Date(timeIntervalSince1970: Double(tv.tv_sec))
    }

    private static func readDisk() -> DiskInfo {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ) else { return DiskInfo() }
        return DiskInfo(
            total: UInt64(max(values.volumeTotalCapacity ?? 0, 0)),
            free: UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        )
    }

    private static func interfaceCounters() -> (inBytes: UInt64, outBytes: UInt64) {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length: size_t = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        let primaryName = primaryInterfaceName()

        return buffer.withUnsafeBytes { raw in
            var inTotal: UInt64 = 0
            var outTotal: UInt64 = 0
            var offset = 0
            var currentName: [CChar] = []

            while offset + MemoryLayout<if_msghdr2>.size <= raw.count {
                let header = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
                switch Int32(header.ifm_type) {
                case RTM_IFINFO2:
                    if currentName == primaryName {
                        let data = header.ifm_data
                        inTotal += UInt64(data.ifi_ibytes)
                        outTotal += UInt64(data.ifi_obytes)
                    }
                case RTM_IFINFO:
                    let nameOffset = offset + MemoryLayout<if_msghdr>.size
                    if nameOffset + 16 <= raw.count {
                        var name: [CChar] = []
                        for i in nameOffset..<(nameOffset + 16) {
                            let byte = raw.loadUnaligned(fromByteOffset: i, as: Int8.self)
                            if byte == 0 { break }
                            name.append(byte)
                        }
                        currentName = name
                    }
                default:
                    break
                }
                if header.ifm_msglen == 0 { break }
                offset += Int(header.ifm_msglen)
            }
            return (inTotal, outTotal)
        }
    }

    private static func primaryInterfaceName() -> [CChar] {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, NET_RT_DUMP2, 0]
        var length: size_t = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [] }

        var best: (index: UInt32, priority: Int) = (0, Int.max)
        return buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<rt_msghdr2>.size <= raw.count {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr2.self)
                if header.rtm_flags & RTF_GATEWAY != 0, header.rtm_addrs & RTA_DST != 0 {
                    if best.index == 0 || UInt32(header.rtm_index) < best.index {
                        best = (UInt32(header.rtm_index), 0)
                    }
                }
                if header.rtm_msglen == 0 { break }
                offset += Int(header.rtm_msglen)
            }

            guard best.index > 0 else { return [] }
            let index: UInt32 = best.index
            var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
            if if_indextoname(index, &name) != nil {
                return Array(name.prefix { $0 != 0 })
            }
            return []
        }
    }
}
