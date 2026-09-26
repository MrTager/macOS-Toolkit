import Foundation

func counters() -> (inBytes: UInt64, outBytes: UInt64) {
    var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length: size_t = 0
    guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
    var buffer = [CChar](repeating: 0, count: length)
    guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }
    return buffer.withUnsafeBytes { raw -> (UInt64, UInt64) in
        var inTotal: UInt64 = 0
        var outTotal: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= raw.count {
            let header = raw.load(fromByteOffset: offset, as: if_msghdr2.self)
            if header.ifm_type == UInt8(RTM_IFINFO2) {
                let data = header.ifm_data
                if data.ifi_type != UInt8(IFT_LOOP) {
                    inTotal += UInt64(data.ifi_ibytes)
                    outTotal += UInt64(data.ifi_obytes)
                }
            }
            if header.ifm_msglen == 0 { break }
            offset += Int(header.ifm_msglen)
        }
        return (inTotal, outTotal)
    }
}

let a = counters()
print("第1次采样: in=\(a.inBytes) out=\(a.outBytes)")
sleep(3)
let b = counters()
print("第2次采样: in=\(b.inBytes) out=\(b.outBytes)")
print("3秒差值: in=\(b.inBytes - a.inBytes)B out=\(b.outBytes - a.outBytes)B")
print("速率: ↓\(Double(b.inBytes - a.inBytes) / 3)B/s ↑\(Double(b.outBytes - a.outBytes) / 3)B/s")
