import Foundation
import IOKit

struct FanInfo: Identifiable {
    let id: Int
    let name: String
    let minRPM: Int
    let maxRPM: Int
    var currentRPM: Int
    var manualMode = false
    var targetRPM: Int = 0
}

struct SensorValue: Identifiable {
    let id: String
    let name: String
    let value: Double
    let unit: String
}

enum FanControlMode: String, Codable {
    case system = "系统自动"
    case manual = "手动恒速"
}

enum FanCurveLevel: Int, Codable, CaseIterable, Identifiable {
    case idle = 0
    case low = 1
    case medium = 2
    case high = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .idle: return "闲时"
        case .low: return "低温"
        case .medium: return "中温"
        case .high: return "高温"
        }
    }
}

final class SMCService: ObservableObject {
    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var sensors: [SensorValue] = []
    @Published private(set) var available = false
    @Published private(set) var helperInstalled = false
    @Published private(set) var mode: FanControlMode = .system
    @Published var curveThresholds: [FanCurveLevel: Double] = [
        .idle: 45, .low: 55, .medium: 65, .high: 75
    ]

    private var conn: io_connect_t = 0
    private var timer: Timer?
    private var curveTimer: Timer?

    private static let fanKeys = ["F0Ac", "F1Ac"]
    private static let fanNameKeys = ["F0ID", "F1ID"]
    private static let fanMinKeys = ["F0Mn", "F1Mn"]
    private static let fanMaxKeys = ["F0Mx", "F1Mx"]

    private static let sensorKeys: [(String, String)] = [
        ("TC0P", "CPU 近端"), ("TC0C", "CPU 核心"), ("TC0D", "CPU 二极管"), ("TC0E", "CPU 封装"),
        ("TC0H", "CPU 散热器"), ("TC0J", "CPU PECI"), ("TCAD", "CPU 相邻"),
        ("TC1C", "核心1"), ("TC2C", "核心2"), ("TC3C", "核心3"), ("TC4C", "核心4"),
        ("TC5C", "核心5"), ("TC6C", "核心6"), ("TC7C", "核心7"), ("TC8C", "核心8"),
        ("TG0P", "GPU 近端"), ("TG0D", "GPU 二极管"), ("TG0H", "GPU 散热器"),
        ("TM0P", "内存槽近端"), ("TM0S", "内存槽1"), ("TM8P", "内存槽2"), ("TM9P", "内存槽3"),
        ("TA0P", "环境"), ("TB0T", "电池"), ("TB1T", "电池1"), ("TB2T", "电池2"),
        ("TW0P", "无线网卡"), ("TL0P", "雷电"), ("TMCD", "主板"), ("Ts0S", "内存 proximity"),
        ("PCPG", "CPU 功耗"), ("PCPL", "平台功耗"), ("PCPT", "CPU 总功耗"), ("PSTR", "系统总功耗")
    ]

    func start() {
        helperInstalled = SMCHelperBridge.ping()
        if helperInstalled {
            discoverFans()
            discoverSensors()
            guard !fans.isEmpty || !sensors.isEmpty else { return }
            available = true
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func installHelper() {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = SMCHelperBridge.install() && SMCHelperBridge.ping()
            DispatchQueue.main.async {
                self.helperInstalled = ok
                if ok {
                    self.start()
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        curveTimer?.invalidate()
    }

    deinit {
        stop()
    }

    private func readKey(_ fourCC: String) -> (type: String, size: Int, data: [UInt8])? {
        guard helperInstalled else { return nil }
        return SMCHelperBridge.read(key: fourCC)
    }

    private func writeKey(_ fourCC: String, data: [UInt8]) -> Bool {
        guard helperInstalled else { return false }
        return SMCHelperBridge.write(key: fourCC, data: data)
    }

    private func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private func numeric(_ typeName: String, _ data: [UInt8]) -> Double? {
        guard data.count >= 2 else { return nil }
        switch typeName {
        case "sp78":
            let raw = Int16(bitPattern: (UInt16(data[0]) << 8) | UInt16(data[1]))
            return Double(raw) / 256.0
        case "fpe2":
            return Double((UInt16(data[0]) << 8) | UInt16(data[1])) / 4.0
        case "fp2e":
            return Double((UInt16(data[0]) << 8) | UInt16(data[1])) / 16384.0
        case "sp5a":
            return Double(Int8(bitPattern: data[0])) / 32.0
        case "ui8 ", "ui8":
            return Double(data[0])
        case "ui16":
            return Double((UInt16(data[0]) << 8) | UInt16(data[1]))
        case "ui32":
            guard data.count >= 4 else { return nil }
            let v = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
            return Double(v)
        default:
            return nil
        }
    }

    private func discoverFans() {
        var discovered: [FanInfo] = []
        for (index, _) in Self.fanKeys.enumerated() {
            guard let (_, _, rpmData) = readKey(Self.fanKeys[index]),
                  let rpm = numeric("fpe2", rpmData) else { continue }

            var name = "风扇 \(index)"
            if let (_, _, nameData) = readKey(Self.fanNameKeys[index]), nameData.count >= 4 {
                let length = min(Int(nameData[0]), nameData.count - 1)
                if length > 1, let decoded = String(bytes: nameData[1...length], encoding: .utf8) {
                    name = decoded
                }
            }

            let minRPM = readKey(Self.fanMinKeys[index]).flatMap { numeric("fpe2", $0.data) }.map(Int.init) ?? 1200
            let maxRPM = readKey(Self.fanMaxKeys[index]).flatMap { numeric("fpe2", $0.data) }.map(Int.init) ?? 6000
            discovered.append(FanInfo(
                id: index,
                name: name,
                minRPM: minRPM,
                maxRPM: maxRPM,
                currentRPM: Int(rpm)
            ))
        }
        fans = discovered
    }

    private func discoverSensors() {
        var found: [SensorValue] = []
        for (key, label) in Self.sensorKeys {
            guard let (type, _, data) = readKey(key),
                  let value = numeric(type, data) else { continue }
            let isTemp = type.hasPrefix("sp") || type == "fpe2" || type == "fp2e"
            guard value > 0, value < 120 else { continue }
            if isTemp && value < 1 { continue }
            found.append(SensorValue(
                id: key,
                name: label,
                value: value,
                unit: key.hasPrefix("P") ? "W" : "°C"
            ))
        }
        sensors = found.sorted { $0.name < $1.name }
    }

    func refresh() {
        var updated = fans
        for index in updated.indices {
            if let (_, _, data) = readKey(Self.fanKeys[updated[index].id]),
               let rpm = numeric("fpe2", data) {
                updated[index].currentRPM = Int(rpm)
            }
        }
        fans = updated

        var updatedSensors: [SensorValue] = []
        for sensor in sensors {
            if let (type, _, data) = readKey(sensor.id),
               let value = numeric(type, data), value > 0, value < 130 {
                updatedSensors.append(SensorValue(id: sensor.id, name: sensor.name, value: value, unit: sensor.unit))
            }
        }
        sensors = updatedSensors
    }

    var cpuTemperature: Double? {
        sensors.first { $0.id == "TC0P" }?.value
            ?? sensors.first { $0.id.hasPrefix("TC") && $0.unit == "°C" }?.value
    }

    func setManualRPM(_ rpm: Int, fan: Int = 0) {
        let clamped = max(fans.first { $0.id == fan }?.minRPM ?? 1200,
                          min(rpm, fans.first { $0.id == fan }?.maxRPM ?? 6000))
        let value = UInt16(clamped)
        let data = [UInt8(value >> 8), UInt8(value & 0xFF)]
        if writeKey("F0Md", data: [0x01]) {
            _ = writeKey(fan == 0 ? "F0Tg" : "F1Tg", data: data)
            mode = .manual
        }
    }

    func setSystemControl() {
        _ = writeKey("F0Md", data: [0x00])
        mode = .system
    }

    private func applyCurveIfActive() {
        guard mode == .system else { return }
    }
}
