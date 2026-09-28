import AppKit
import TouchBarBridge

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private enum Item {
        static let network = NSTouchBarItem.Identifier("local.toolkit.touchbar.network")
        static let cpu = NSTouchBarItem.Identifier("local.toolkit.touchbar.cpu")
        static let fan = NSTouchBarItem.Identifier("local.toolkit.touchbar.fan")
        static let temperature = NSTouchBarItem.Identifier("local.toolkit.touchbar.temperature")
        static let memory = NSTouchBarItem.Identifier("local.toolkit.touchbar.memory")
        static let disk = NSTouchBarItem.Identifier("local.toolkit.touchbar.disk")
        static let resources = NSTouchBarItem.Identifier("local.toolkit.touchbar.resources")
        static let openWindow = NSTouchBarItem.Identifier("local.toolkit.touchbar.open-window")

        static let ordered: [NSTouchBarItem.Identifier] = [
            network, cpu, fan, temperature, resources, openWindow
        ]
    }

    private let openWindow: () -> Void
    private var buttons: [NSTouchBarItem.Identifier: [NSButton]] = [:]
    private var progressValues: [NSTouchBarItem.Identifier: [NSTextField]] = [:]
    private var progressBars: [NSTouchBarItem.Identifier: [TouchBarGradientProgressView]] = [:]
    private let bar = NSTouchBar()
    private let persistentBar = NSTouchBar()
    private let trayIdentifier = NSTouchBarItem.Identifier("local.toolkit.touchbar.persistent")
    private var trayItem: NSCustomTouchBarItem?
    private var registered = false
    private(set) var isPersistentVisible = false

    private var networkTitle = "↓ --  ↑ --"
    private var downloadSpeed = "--"
    private var uploadSpeed = "--"
    private var cpuTitle = "CPU --%"
    private var cpuValue = "--%"
    private var cpuUsage = 0.0
    private var fanTitle = "风扇 --"
    private var fanValue = "--"
    private var temperatureTitle = "温度 --°"
    private var temperatureValue = "--°"
    private var temperatureCelsius: Double?
    private var memoryValue = "--%"
    private var diskValue = "--%"
    private var memoryPercent = 0.0
    private var diskPercent = 0.0

    init(openWindow: @escaping () -> Void) {
        self.openWindow = openWindow
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = Item.ordered
        persistentBar.delegate = self
        persistentBar.defaultItemIdentifiers = Item.ordered
    }

    func install(on window: NSWindow?) {
        NSApp.touchBar = bar
        window?.touchBar = bar
    }

    func installOnPopover(_ popover: NSPopover) {
        popover.contentViewController?.view.window?.touchBar = bar
    }

    @discardableResult
    func installPersistent() -> Bool {
        guard toolkit_touchbar_supported() else { return false }
        if !registered {
            let item = NSCustomTouchBarItem(identifier: trayIdentifier)
            let button = NSButton(title: networkTitle, target: self, action: #selector(togglePersistent(_:)))
            button.toolTip = "展开或收起 Toolkit Touch Bar"
            styleMetricButton(button, identifier: Item.network)
            item.view = button
            item.customizationLabel = "Toolkit 网速与状态"
            guard toolkit_touchbar_register(item) else { return false }
            trayItem = item
            registered = true
        }
        return true
    }

    @discardableResult
    func presentPersistent() -> Bool {
        guard installPersistent() else { return false }
        let items = Item.ordered.compactMap { persistentBar.item(forIdentifier: $0) }
        guard items.count == Item.ordered.count else { return false }
        persistentBar.templateItems = Set(items)
        isPersistentVisible = toolkit_touchbar_present(persistentBar, trayIdentifier.rawValue)
        return isPersistentVisible
    }

    func dismissPersistent() {
        toolkit_touchbar_dismiss(persistentBar)
        isPersistentVisible = false
    }

    func restoreAfterWake() {
        dismissPersistent()
        if let trayItem, registered { toolkit_touchbar_unregister(trayItem) }
        registered = false
        _ = presentPersistent()
    }

    func uninstallPersistent() {
        dismissPersistent()
        if let trayItem, registered { toolkit_touchbar_unregister(trayItem) }
        registered = false
        trayItem = nil
    }

    func update(network: NetworkInfo, cpu: CPUInfo, fans: [FanInfo], temperature: Double?, memory: MemoryInfo, disk: DiskInfo) {
        downloadSpeed = Self.shortSpeed(network.inRate)
        uploadSpeed = Self.shortSpeed(network.outRate)
        networkTitle = "↓\(downloadSpeed) ↑\(uploadSpeed)"
        cpuUsage = cpu.overall
        cpuValue = "\(Int(cpu.overall.rounded()))%"
        cpuTitle = "CPU \(cpuValue)"
        fanValue = fans.first.map { "\($0.currentRPM)" } ?? "--"
        fanTitle = "风扇 \(fanValue)"
        temperatureCelsius = temperature
        temperatureValue = temperature.map { "\(Int($0.rounded()))°" } ?? "--°"
        temperatureTitle = "温度 \(temperatureValue)"
        memoryPercent = Self.usedPercent(used: memory.used, total: memory.total)
        diskPercent = Self.usedPercent(used: disk.total >= disk.free ? disk.total - disk.free : 0, total: disk.total)
        memoryValue = memory.total > 0 ? "\(Int(memoryPercent.rounded()))%" : "--%"
        diskValue = disk.total > 0 ? "\(Int(diskPercent.rounded()))%" : "--%"

        for identifier in [Item.network, Item.cpu, Item.fan, Item.temperature] {
            buttons[identifier]?.forEach { styleMetricButton($0, identifier: identifier) }
        }
        progressValues[Item.memory]?.forEach { $0.stringValue = memoryValue }
        progressValues[Item.disk]?.forEach { $0.stringValue = diskValue }
        progressBars[Item.memory]?.forEach { $0.fraction = memoryPercent / 100 }
        progressBars[Item.disk]?.forEach { $0.fraction = diskPercent / 100 }
        if let button = trayItem?.view as? NSButton {
            styleMetricButton(button, identifier: Item.network)
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == Item.resources {
            return makeResourcesItem()
        }
        let title: String
        switch identifier {
        case Item.network: title = networkTitle
        case Item.cpu: title = cpuTitle
        case Item.fan: title = fanTitle
        case Item.temperature: title = temperatureTitle
        case Item.openWindow: title = "打开窗口"
        default: return nil
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: title, target: self, action: #selector(openMainWindow(_:)))
        button.bezelColor = identifier == Item.openWindow ? .controlAccentColor : nil
        button.toolTip = identifier == Item.openWindow ? "打开 macOS Toolkit 主窗口" : "查看详情并打开主窗口"
        if identifier != Item.openWindow { styleMetricButton(button, identifier: identifier) }
        item.view = button
        item.customizationLabel = title
        buttons[identifier, default: []].append(button)
        return item
    }

    private func makeResourcesItem() -> NSTouchBarItem {
        let stack = NSStackView(views: [
            makeResourceRow(identifier: Item.memory),
            makeResourceRow(identifier: Item.disk)
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1

        let item = NSCustomTouchBarItem(identifier: Item.resources)
        item.view = stack
        item.customizationLabel = "内存与磁盘"
        return item
    }

    private func makeResourceRow(identifier: NSTouchBarItem.Identifier) -> NSView {
        let isMemory = identifier == Item.memory
        let colors: (NSColor, NSColor) = isMemory
            ? (NSColor(srgbRed: 0.21, green: 0.91, blue: 1, alpha: 1), NSColor(srgbRed: 0.57, green: 0.42, blue: 1, alpha: 1))
            : (NSColor(srgbRed: 0.55, green: 0.48, blue: 1, alpha: 1), NSColor(srgbRed: 1, green: 0.36, blue: 0.73, alpha: 1))
        let label = NSTextField(labelWithString: isMemory ? "内存" : "磁盘")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let value = NSTextField(labelWithString: isMemory ? memoryValue : diskValue)
        value.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        value.alignment = .center
        value.textColor = colors.0
        value.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let progress = TouchBarGradientProgressView(startColor: colors.0, endColor: colors.1)
        progress.fraction = (isMemory ? memoryPercent : diskPercent) / 100
        progress.widthAnchor.constraint(equalToConstant: 96).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 7).isActive = true

        let row = NSStackView(views: [label, progress, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4

        progressValues[identifier, default: []].append(value)
        progressBars[identifier, default: []].append(progress)
        return row
    }

    private func styleMetricButton(_ button: NSButton, identifier: NSTouchBarItem.Identifier) {
        let title = NSMutableAttributedString()
        let font = button.font ?? NSFont.systemFont(ofSize: 13)
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

        func append(_ text: String, color: NSColor? = nil) {
            var attributes = normal
            if let color { attributes[.foregroundColor] = color }
            title.append(NSAttributedString(string: text, attributes: attributes))
        }

        switch identifier {
        case Item.network:
            append("↓")
            append(downloadSpeed, color: NSColor(srgbRed: 0.27, green: 0.85, blue: 1, alpha: 1))
            append(" ↑")
            append(uploadSpeed, color: NSColor(srgbRed: 0.35, green: 0.91, blue: 0.62, alpha: 1))
        case Item.cpu:
            append("CPU ")
            append(cpuValue, color: cpuUsage < 60 ? .systemGreen : (cpuUsage < 85 ? .systemYellow : .systemRed))
        case Item.fan:
            append("风扇 ")
            append(fanValue, color: NSColor(srgbRed: 0.66, green: 0.58, blue: 1, alpha: 1))
        case Item.temperature:
            append("温度 ")
            let color: NSColor = temperatureCelsius.map {
                $0 < 60 ? .systemTeal : ($0 < 85 ? .systemOrange : .systemRed)
            } ?? .secondaryLabelColor
            append(temperatureValue, color: color)
        default:
            return
        }
        button.attributedTitle = title
    }

    @objc private func togglePersistent(_ sender: Any?) {
        if isPersistentVisible { dismissPersistent() }
        else { _ = presentPersistent() }
    }

    @objc private func openMainWindow(_ sender: Any?) {
        openWindow()
    }

    private static func shortSpeed(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1024 { return "\(Int(value.rounded()))B/s" }
        if value < 1024 * 1024 { return String(format: "%.1fK/s", value / 1024) }
        if value < 1024 * 1024 * 1024 { return String(format: "%.1fM/s", value / 1024 / 1024) }
        return String(format: "%.1fG/s", value / 1024 / 1024 / 1024)
    }

    private static func usedPercent(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(total) * 100))
    }
}

private final class TouchBarGradientProgressView: NSView {
    private let startColor: NSColor
    private let endColor: NSColor

    var fraction = 0.0 {
        didSet { needsDisplay = true }
    }

    init(startColor: NSColor, endColor: NSColor) {
        self.startColor = startColor
        self.endColor = endColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
        NSColor.white.withAlphaComponent(0.12).setFill()
        track.fill()

        let inner = trackRect.insetBy(dx: 1, dy: 1)
        let width = inner.width * min(1, max(0, fraction))
        if width > 0 {
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: max(width, inner.height), height: inner.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: inner.height / 2, yRadius: inner.height / 2)
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = endColor.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 3
            glow.set()
            NSGradient(starting: startColor, ending: endColor)?.draw(in: fill, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }

        startColor.withAlphaComponent(0.9).setStroke()
        track.lineWidth = 1
        track.stroke()
    }
}
