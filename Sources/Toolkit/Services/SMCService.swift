import Foundation
import SMCCore

struct FanInfo: Identifiable {
    let id: Int
    let name: String
    let minRPM: Int
    let maxRPM: Int
    var currentRPM: Int
    var targetRPM: Int
    var manualMode: Bool
}

struct SensorValue: Identifiable {
    let id: String
    let name: String
    let value: Double
    let unit: String
}

enum FanSetting: Equatable {
    case system
    case constant(Int)
    case sensor(key: String, low: Double, high: Double)
}

final class SMCService: ObservableObject {
    @Published private(set) var fans: [FanInfo] = []
    @Published private(set) var sensors: [SensorValue] = []
    @Published private(set) var available = false
    @Published private(set) var helperInstalled = false
    @Published private(set) var settings: [Int: FanSetting] = [:]
    @Published private(set) var errorMessage: String?

    private var timer: Timer?
    private var previousTargets: [Int: Int] = [:]
    private static let sensorKeys: [(String, String)] = [
        ("TC0P", "CPU 近端"), ("TC0C", "CPU 核心"), ("TC0D", "CPU 二极管"), ("TC0E", "CPU 封装"),
        ("TC0H", "CPU 散热器"), ("TC0J", "CPU PECI"), ("TCAD", "CPU 相邻"),
        ("TC1C", "核心1"), ("TC2C", "核心2"), ("TC3C", "核心3"), ("TC4C", "核心4"),
        ("TC5C", "核心5"), ("TC6C", "核心6"), ("TC7C", "核心7"), ("TC8C", "核心8"),
        ("TG0P", "GPU 近端"), ("TG0D", "GPU 二极管"), ("TG0H", "GPU 散热器"),
        ("TM0P", "内存槽近端"), ("TM0S", "内存槽1"), ("TM8P", "内存槽2"), ("TM9P", "内存槽3"),
        ("TA0P", "环境"), ("TB0T", "电池"), ("TB1T", "电池1"), ("TB2T", "电池2"),
        ("TW0P", "无线网卡"), ("TL0P", "雷电"), ("TMCD", "主板")
    ]

    func start() {
        timer?.invalidate()
        helperInstalled = SMCHelperBridge.ping()
        discover()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func installHelper() {
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = SMCHelperBridge.install() && SMCHelperBridge.ping()
            DispatchQueue.main.async {
                self.helperInstalled = installed
                self.errorMessage = installed ? nil : "特权助手安装失败，风扇保持系统自动控制"
            }
        }
    }

    func stop() {
        timer?.invalidate()
        for fan in fans where settings[fan.id] != nil { _ = setSystemControl(fan: fan.id) }
    }

    private func read(_ key: String) -> (type: String, data: [UInt8])? {
        var value = ToolkitSMCValue()
        guard toolkit_smc_read(key, &value), value.size > 0 else { return nil }
        let type = withUnsafeBytes(of: value.type) { raw in String(bytes: raw.prefix(4), encoding: .ascii) ?? "" }
        let data = withUnsafeBytes(of: value.bytes) { raw in Array(raw.prefix(Int(value.size))) }
        return (type, data)
    }

    private func numeric(_ key: String) -> Double? {
        guard let (type, bytes) = read(key) else { return nil }
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = bytes.prefix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
            return Double(Float(bitPattern: bits))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 ", "ui8", "flag": return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default: return nil
        }
    }

    private func discover() {
        let count = min(10, max(0, Int(numeric("FNum") ?? 0)))
        fans = (0..<count).compactMap { id in
            let key = "F\(id)"
            guard let current = numeric(key + "Ac"), let lower = numeric(key + "Mn"),
                  let upper = numeric(key + "Mx"), upper > lower else { return nil }
            return FanInfo(id: id, name: "风扇 \(id + 1)", minRPM: Int(lower), maxRPM: Int(upper),
                           currentRPM: Int(current), targetRPM: Int(numeric(key + "Tg") ?? current),
                           manualMode: numeric(key + "Md") == 1)
        }
        sensors = Self.sensorKeys.compactMap { key, label in
            guard let value = numeric(key), value > 0, value < 130 else { return nil }
            return SensorValue(id: key, name: label, value: value, unit: "°C")
        }
        available = !fans.isEmpty
    }

    func refresh() {
        if helperInstalled && !SMCHelperBridge.ping() {
            helperInstalled = false
            settings.removeAll()
            errorMessage = "风扇控制助手已断开"
        }
        for index in fans.indices {
            let key = "F\(fans[index].id)"
            if let value = numeric(key + "Ac") { fans[index].currentRPM = Int(value) }
            if let value = numeric(key + "Tg") { fans[index].targetRPM = Int(value) }
            if let value = numeric(key + "Md") { fans[index].manualMode = value == 1 }
        }
        sensors = sensors.compactMap { sensor in
            guard let value = numeric(sensor.id), value > 0, value < 130 else { return nil }
            return SensorValue(id: sensor.id, name: sensor.name, value: value, unit: sensor.unit)
        }
        for (id, setting) in settings {
            if case let .sensor(key, low, high) = setting {
                guard let fan = fans.first(where: { $0.id == id }) else { continue }
                guard let temperature = sensors.first(where: { $0.id == key })?.value else {
                    _ = setSystemControl(fan: id)
                    errorMessage = "温度传感器失效，风扇 \(id + 1) 已恢复系统自动控制"
                    continue
                }
                let fraction = max(0, min(1, (temperature - low) / (high - low)))
                let rpm = Int((Double(fan.minRPM) + fraction * Double(fan.maxRPM - fan.minRPM)).rounded())
                if previousTargets[id] != rpm { _ = writeRPM(rpm, fan: id) }
            }
        }
    }

    var cpuTemperature: Double? {
        sensors.first { $0.id == "TC0P" }?.value ?? sensors.first { $0.id.hasPrefix("TC") }?.value
    }

    @discardableResult
    func setSystemControl(fan id: Int) -> Bool {
        guard helperInstalled, fans.contains(where: { $0.id == id }) else { return false }
        let ok = SMCHelperBridge.write(key: "F\(id)Md", data: [0])
        if ok { settings[id] = nil; previousTargets[id] = nil; refresh() }
        else { errorMessage = "恢复风扇 \(id + 1) 自动控制失败" }
        return ok
    }

    @discardableResult
    func setConstantRPM(_ rpm: Int, fan id: Int) -> Bool {
        guard let fan = fans.first(where: { $0.id == id }), helperInstalled else { return false }
        let safe = max(fan.minRPM, min(fan.maxRPM, rpm))
        guard writeRPM(safe, fan: id) else { return false }
        settings[id] = .constant(safe)
        return true
    }

    @discardableResult
    func setSensorControl(fan id: Int, sensor key: String, low: Double, high: Double) -> Bool {
        guard high > low + 1, sensors.contains(where: { $0.id == key }),
              fans.contains(where: { $0.id == id }), helperInstalled else { return false }
        settings[id] = .sensor(key: key, low: low, high: high)
        previousTargets[id] = nil
        refresh()
        let success = previousTargets[id] != nil
        if !success { settings[id] = nil }
        return success
    }

    private func writeRPM(_ rpm: Int, fan id: Int) -> Bool {
        let bits = Float(rpm).bitPattern
        let bytes = (0..<4).map { UInt8((bits >> ($0 * 8)) & 0xff) }
        let key = "F\(id)"
        if fans.first(where: { $0.id == id })?.manualMode != true {
            guard SMCHelperBridge.write(key: key + "Md", data: [1]) else {
                errorMessage = "风扇 \(id + 1) 无法进入手动模式"
                return false
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard SMCHelperBridge.write(key: key + "Tg", data: bytes) else {
            errorMessage = "风扇 \(id + 1) 设置失败，已尝试恢复自动控制"
            _ = SMCHelperBridge.write(key: key + "Md", data: [0])
            return false
        }
        Thread.sleep(forTimeInterval: 0.1)
        guard let observed = numeric(key + "Tg"), abs(observed - Double(rpm)) <= 5 else {
            errorMessage = "风扇 \(id + 1) 未接受目标转速，已尝试恢复自动控制"
            _ = SMCHelperBridge.write(key: key + "Md", data: [0])
            return false
        }
        if let index = fans.firstIndex(where: { $0.id == id }) {
            fans[index].manualMode = true
            fans[index].targetRPM = rpm
        }
        previousTargets[id] = rpm
        return true
    }
}
