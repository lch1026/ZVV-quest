import Foundation
import IOKit

/// 读取 Apple GPU 的利用率。系统不允许访问时返回 nil，界面会自动退化为显存占用曲线。
final class IOKitGPUReader {
    private var iterator: io_iterator_t = 0
    private var service: io_registry_entry_t = 0
    let isAvailable: Bool

    init() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            isAvailable = false
            return
        }
        var found: io_registry_entry_t = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any],
               dictionary["PerformanceStatistics"] != nil {
                found = entry
                break
            }
            IOObjectRelease(entry)
        }
        IOObjectRelease(iterator)
        service = found
        isAvailable = found != 0
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    /// 0...1 的 GPU 利用率
    var utilization: Double? {
        guard let statistics = performanceStatistics else { return nil }

        let keys = ["Device Utilization %", "GPU Activity(%)", "gpu_utilization", "Utilization %"]
        for key in keys {
            if let value = statistics[key] as? Int { return min(1, max(0, Double(value) / 100)) }
            if let value = statistics[key] as? Double { return min(1, max(0, value / 100)) }
        }
        return nil
    }

    /// GPU 当前占用的系统内存（字节）
    var inUseMemoryBytes: Int64? {
        guard let statistics = performanceStatistics else { return nil }
        for key in ["In use system memory", "In use system memory (driver)", "Alloc system memory"] {
            if let value = statistics[key] as? Int64, value > 0 { return value }
            if let value = statistics[key] as? Int, value > 0 { return Int64(value) }
        }
        return nil
    }

    private var performanceStatistics: [String: Any]? {
        guard service != 0 else { return nil }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return dictionary["PerformanceStatistics"] as? [String: Any]
    }
}
