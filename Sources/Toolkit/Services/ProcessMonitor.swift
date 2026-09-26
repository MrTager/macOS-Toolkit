import Foundation

struct ProcessEntry: Identifiable, Equatable {
    let id: Int32
    let pid: Int32
    let name: String
    var cpu: Double
    var memory: UInt64
    var threads: Int
    var user: String

    static func == (lhs: ProcessEntry, rhs: ProcessEntry) -> Bool {
        lhs.pid == rhs.pid && lhs.cpu == rhs.cpu && lhs.memory == rhs.memory
    }
}

final class ProcessMonitor: ObservableObject {
    @Published private(set) var entries: [ProcessEntry] = []
    @Published var sortBy: SortKey = .cpu {
        didSet { refresh() }
    }
    @Published var filterText: String = "" {
        didSet { refresh() }
    }
    @Published private(set) var totalProcesses = 0

    enum SortKey {
        case cpu, memory, name
    }

    private var timer: Timer?
    private var prevCpuTimes: [Int32: UInt64] = [:]
    private var lastTick: Date?
    private let currentUID = getuid()

    func start(interval: TimeInterval = 2) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let now = Date()
        let elapsed = lastTick.map { max(now.timeIntervalSince($0), 0.2) }
        lastTick = now

        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return }
        var pids = [Int32](repeating: 0, count: Int(bufferSize))
        let count = proc_listallpids(&pids, bufferSize)
        guard count > 0 else { return }
        let pidList = Array(pids.prefix(Int(count)))

        var nextCpuTimes: [Int32: UInt64] = [:]
        var results: [ProcessEntry] = []
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

        for pid in pidList where pid > 0 {
            var rusage = rusage_info_current()
            let result = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
                var info: rusage_info_t? = UnsafeMutableRawPointer(ptr)
                return withUnsafeMutablePointer(to: &info) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard result == 0 else { continue }

            let cpuNanos = rusage.ri_user_time + rusage.ri_system_time
            nextCpuTimes[pid] = cpuNanos

            let memory = UInt64(rusage.ri_resident_size)
            let name = Self.processName(pid: pid) ?? "pid \(pid)"
            let user = Self.userName(uid: Self.userId(pid: pid))

            var cpuPercent = 0.0
            if let elapsed, let prev = prevCpuTimes[pid], cpuNanos >= prev {
                let deltaSeconds = Double(cpuNanos - prev) / 1_000_000_000
                cpuPercent = min(deltaSeconds / elapsed * cores * 100, 100 * cores)
            }

            results.append(ProcessEntry(
                id: pid,
                pid: pid,
                name: name,
                cpu: cpuPercent,
                memory: memory,
                threads: 0,
                user: user
            ))
        }

        prevCpuTimes = nextCpuTimes
        totalProcesses = results.count

        let keyword = filterText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            results = results.filter {
                $0.name.localizedCaseInsensitiveContains(keyword) || String($0.pid).contains(keyword)
            }
        }

        switch sortBy {
        case .cpu: results.sort { $0.cpu == $1.cpu ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        case .memory: results.sort { $0.memory == $1.memory ? $0.cpu > $1.cpu : $0.memory > $1.memory }
        case .name: results.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }

        entries = Array(results.prefix(80))
    }

    func terminate(_ pid: Int32, force: Bool = false) -> Bool {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, signal) == 0
    }

    private static func processName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        return (path as NSString).lastPathComponent
    }

    private static func userId(pid: Int32) -> UInt32 {
        var info = proc_bsdinfo()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, UnsafeMutableRawPointer(ptr), Int32(MemoryLayout<proc_bsdinfo>.size))
        }
        guard result > 0 else { return UInt32(getuid()) }
        return info.pbi_uid
    }

    private static func userName(uid: UInt32) -> String {
        if uid == UInt32(getuid()) { return NSFullUserName() }
        guard let passwd = getpwuid(uid), let name = passwd.pointee.pw_gecos, name[0] != 0 else {
            return uid == 0 ? "root" : "uid \(uid)"
        }
        return String(cString: name).components(separatedBy: ",").first ?? "uid \(uid)"
    }
}
