import Darwin
import Foundation

/// The process's physical footprint in bytes, as Xcode's memory gauge shows it. Readings
/// in the simulator are steady to within 0.1 MiB.
func physicalFootprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS, "task_info failed: \(result)")
    return Int(info.phys_footprint)
}
