import Foundation
import IOKit

struct SensorReading: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let unit: String
}

final class TempSensorService: ObservableObject {
    @Published private(set) var readings: [SensorReading] = []
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var batteryTemperature: Double?
    @Published private(set) var available = false

    private var timer: Timer?
    private var batteryPort: io_registry_entry_t = 0

    func start(interval: TimeInterval = 3) {
        openBattery()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    deinit {
        if batteryPort != 0 {
            IOObjectRelease(batteryPort)
        }
        timer?.invalidate()
    }

    private func openBattery() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        if entry != 0 {
            batteryPort = entry
        }
    }

    private func sample() {
        var results: [SensorReading] = []

        if let battery = readBatteryTemperature() {
            batteryTemperature = battery
            results.append(SensorReading(name: "电池", value: battery, unit: "°C"))
        }

        if let thermalPressure = readThermalPressure() {
            results.append(SensorReading(name: "CPU 热压力", value: thermalPressure, unit: ""))
        }

        available = !results.isEmpty
        readings = results
    }

    private func readBatteryTemperature() -> Double? {
        if batteryPort == 0 {
            openBattery()
            guard batteryPort != 0 else { return nil }
        }
        guard let unmanaged = IORegistryEntryCreateCFProperty(batteryPort, "Temperature" as CFString, kCFAllocatorDefault, 0),
              let number = unmanaged.takeRetainedValue() as? NSNumber else {
            return nil
        }
        let raw = number.intValue
        guard raw > 0 else { return nil }
        return Double(raw) / 100.0
    }

    private func readThermalPressure() -> Double? {
        var name: [CChar] = [0, 0, 0, 0]
        var length = 4
        guard sysctlbyname("kern.thermalpressure", &name, &length, nil, 0) == 0, name[0] != 0 else {
            return nil
        }
        let level = String(cString: name)
        switch level {
        case "NOMINAL": return 0
        case "FAIR": return 25
        case "SERIOUS": return 50
        case "CRITICAL": return 75
        case "SLEEPING": return 0
        default: return 0
        }
    }
}
