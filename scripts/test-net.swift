import Foundation
import SystemConfiguration

func primaryInterfaceName() -> String? {
    guard let store = SCDynamicStoreCreate(nil, "test" as CFString, nil, nil) else { return nil }
    guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
    return global["PrimaryInterface"] as? String
}

func interfaceCounters() -> (inBytes: UInt64, outBytes: UInt64) {
    var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length: size_t = 0
    guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
    var buffer = [CChar](repeating: 0, count: length)
    guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

    guard let primary = primaryInterfaceName() else { return (0, 0) }

    return buffer.withUnsafeBytes { raw in
        var inTotal: UInt64 = 0
        var outTotal: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= raw.count {
            let header = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
            if header.ifm_type == UInt8(RTM_IFINFO2) {
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(header.ifm_index), &name) != nil {
                    let ifName = String(cString: name)
                    if ifName == primary {
                        let data = header.ifm_data
                        inTotal += UInt64(data.ifi_ibytes)
                        outTotal += UInt64(data.ifi_obytes)
                    }
                }
            }
            if header.ifm_msglen == 0 { break }
            offset += Int(header.ifm_msglen)
        }
        return (inTotal, outTotal)
    }
}

print("主网卡: \(primaryInterfaceName() ?? "未识别")")
let a = interfaceCounters()
print("第1次: in=\(a.inBytes) out=\(a.outBytes)")
sleep(3)
let b = interfaceCounters()
print("第2次: in=\(b.inBytes) out=\(b.outBytes)")
print("3秒差值: ↓\(b.inBytes - a.inBytes)B ↑\(b.outBytes - a.outBytes)B")
