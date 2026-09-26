import Combine
import Foundation
import UserNotifications

enum RuleMetric: String, Codable, CaseIterable, Identifiable {
    case cpu = "CPU 使用率"
    case memory = "内存使用率"
    case batteryTemp = "电池温度"
    case thermalPressure = "CPU 热压力"

    var id: String { rawValue }
    var unit: String {
        switch self {
        case .cpu, .memory: return "%"
        case .batteryTemp: return "°C"
        case .thermalPressure: return "分"
        }
    }
    var defaultThreshold: Double {
        switch self {
        case .cpu: return 90
        case .memory: return 90
        case .batteryTemp: return 40
        case .thermalPressure: return 50
        }
    }
}

struct AlertRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var metric: RuleMetric
    var threshold: Double
    var enabled = true
    var cooldownMinutes = 10
}

final class RuleEngine: ObservableObject {
    @Published private(set) var rules: [AlertRule] = []
    @Published private(set) var lastEvents: [String] = []
    @Published private(set) var lastCheckResult: [RuleMetric: Double] = [:]

    private var timer: Timer?
    private var lastFired: [UUID: Date] = [:]
    private var monitor: SystemMonitor?
    private var tempSensor: TempSensorService?
    private var grantedNotifications = false

    private static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("macOS Toolkit/rules.json")
    }

    static let defaultRules: [AlertRule] = [
        AlertRule(metric: .cpu, threshold: 90, enabled: false),
        AlertRule(metric: .memory, threshold: 90, enabled: true),
        AlertRule(metric: .batteryTemp, threshold: 40, enabled: true),
        AlertRule(metric: .thermalPressure, threshold: 50, enabled: false)
    ]

    func configure(monitor: SystemMonitor, tempSensor: TempSensorService) {
        self.monitor = monitor
        self.tempSensor = tempSensor
    }

    func start(interval: TimeInterval = 10) {
        load()
        if rules.isEmpty {
            rules = Self.defaultRules
            save()
        }
        requestNotificationPermission()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    func add(_ rule: AlertRule) {
        rules.append(rule)
        save()
    }

    func update(_ rule: AlertRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        lastFired[id] = nil
        save()
    }

    func toggle(_ rule: AlertRule) {
        var updated = rule
        updated.enabled.toggle()
        update(updated)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.grantedNotifications = granted
            }
        }
    }

    private func evaluate() {
        guard let monitor, let tempSensor else { return }

        var metrics: [RuleMetric: Double] = [:]
        metrics[.cpu] = monitor.cpu.overall
        if monitor.memory.total > 0 {
            metrics[.memory] = Double(monitor.memory.used) / Double(monitor.memory.total) * 100
        }
        if let battery = tempSensor.batteryTemperature {
            metrics[.batteryTemp] = battery
        }
        if let pressure = tempSensor.readings.first(where: { $0.unit == "" })?.value {
            metrics[.thermalPressure] = pressure
        }
        lastCheckResult = metrics

        let now = Date()
        for rule in rules where rule.enabled {
            guard let value = metrics[rule.metric] else { continue }
            guard value >= rule.threshold else {
                if let fired = lastFired[rule.id], now.timeIntervalSince(fired) < TimeInterval(rule.cooldownMinutes * 60) {
                    continue
                }
                lastFired[rule.id] = nil
                continue
            }
            if let fired = lastFired[rule.id],
               now.timeIntervalSince(fired) < TimeInterval(rule.cooldownMinutes * 60) {
                continue
            }
            lastFired[rule.id] = now
            fire(rule: rule, value: value)
        }
    }

    private func fire(rule: AlertRule, value: Double) {
        let text = String(format: "%@ 达到 %.1f%@（阈值 %.0f%@）",
                          rule.metric.rawValue, value, rule.metric.unit,
                          rule.threshold, rule.metric.unit)
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lastEvents.insert("[\(stamp)] \(text)", at: 0)
        if lastEvents.count > 30 {
            lastEvents.removeLast(lastEvents.count - 30)
        }

        if grantedNotifications {
            let content = UNMutableNotificationContent()
            content.title = "macOS Toolkit 告警"
            content.body = text
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "rule-\(rule.id.uuidString)-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.configURL) else { return }
        if let loaded = try? JSONDecoder().decode([AlertRule].self, from: data) {
            rules = loaded
        }
    }

    private func save() {
        let url = Self.configURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(rules) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
