import Darwin
import Foundation

struct MachineSnapshot: Equatable {
    var appBytes: UInt64
    var modelBytes: UInt64
    var modelReady: Bool
    var physicalBytes: UInt64
    var processorCount: Int

    var appShare: Double {
        guard physicalBytes > 0 else { return 0 }
        return min(1, Double(appBytes) / Double(physicalBytes))
    }
}

enum MachineLoad {
    static func capture(modelReady: Bool, modelFolder: URL) -> MachineSnapshot {
        capture(modelReady: modelReady, modelBytes: folderBytes(modelFolder))
    }

    /// Lightweight snapshot that reuses a cached on-disk model size (avoids walking the folder).
    static func capture(modelReady: Bool, modelBytes: UInt64) -> MachineSnapshot {
        MachineSnapshot(
            appBytes: physicalFootprint(),
            modelBytes: modelBytes,
            modelReady: modelReady,
            physicalBytes: ProcessInfo.processInfo.physicalMemory,
            processorCount: ProcessInfo.processInfo.processorCount
        )
    }

    static func modelFolderBytes(_ folder: URL) -> UInt64 {
        folderBytes(folder)
    }

    static func megabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_048_576
        if value < 10 {
            return String(format: "%.1f MB", value)
        }
        return String(format: "%.0f MB", value)
    }

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    private static func folderBytes(_ folder: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += UInt64(values?.fileSize ?? 0)
        }
        return total
    }
}
