import Foundation
import Darwin

/// CPU, memory, network and disk figures, sampled every 2 seconds while something is showing them.
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0

    private var timer: Timer?
    private var users = 0
    private var lastTicks: (user: Double, system: Double, idle: Double, nice: Double)?
    private var lastNetwork: (received: UInt64, sent: UInt64, date: Date)?

    /// Calls are counted, so several views can share one sampler.
    func start() {
        users += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastNetwork = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        sampleDisk()
    }

    private func sampleCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let ticks = (user: Double(info.cpu_ticks.0), system: Double(info.cpu_ticks.1),
                     idle: Double(info.cpu_ticks.2), nice: Double(info.cpu_ticks.3))
        if let last = lastTicks {
            let busy = (ticks.user - last.user) + (ticks.system - last.system) + (ticks.nice - last.nice)
            let total = busy + (ticks.idle - last.idle)
            if total > 0 {
                cpu = min(max(busy / total, 0), 1)
                cpuHistory.append(cpu)
                if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
            }
        }
        lastTicks = ticks
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func sampleMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = UInt64(sysconf(_SC_PAGESIZE))
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        memoryUsed = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private func sampleNetwork() {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let flags = Int32(entry.pointee.ifa_flags)
            if let address = entry.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
               let data = entry.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(counters.ifi_ibytes)
                sent += UInt64(counters.ifi_obytes)
            }
            cursor = entry.pointee.ifa_next
        }

        let now = Date()
        if let last = lastNetwork {
            let elapsed = now.timeIntervalSince(last.date)
            if elapsed > 0 {
                downloadRate = received >= last.received ? Double(received - last.received) / elapsed : 0
                uploadRate = sent >= last.sent ? Double(sent - last.sent) / elapsed : 0
            }
        }
        lastNetwork = (received, sent, now)
    }

    private func sampleDisk() {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        diskFree = values?.volumeAvailableCapacityForImportantUsage ?? 0
        diskTotal = Int64(values?.volumeTotalCapacity ?? 0)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}
