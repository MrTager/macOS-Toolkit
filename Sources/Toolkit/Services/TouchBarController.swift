import AppKit

final class TouchBarController: NSObject, NSTouchBarDelegate {
    private enum Item {
        static let network = NSTouchBarItem.Identifier("local.toolkit.touchbar.network")
        static let cpu = NSTouchBarItem.Identifier("local.toolkit.touchbar.cpu")
        static let fan = NSTouchBarItem.Identifier("local.toolkit.touchbar.fan")
        static let temperature = NSTouchBarItem.Identifier("local.toolkit.touchbar.temperature")
        static let openWindow = NSTouchBarItem.Identifier("local.toolkit.touchbar.open-window")

        static let ordered: [NSTouchBarItem.Identifier] = [
            network, cpu, fan, temperature, openWindow
        ]
    }

    private let openWindow: () -> Void
    private var buttons: [NSTouchBarItem.Identifier: NSButton] = [:]
    private let bar = NSTouchBar()

    private var networkTitle = "↓ --  ↑ --"
    private var cpuTitle = "CPU --%"
    private var fanTitle = "风扇 --"
    private var temperatureTitle = "温度 --°"

    init(openWindow: @escaping () -> Void) {
        self.openWindow = openWindow
        super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = Item.ordered
    }

    func install(on window: NSWindow?) {
        NSApp.touchBar = bar
        window?.touchBar = bar
    }

    func installOnPopover(_ popover: NSPopover) {
        popover.contentViewController?.view.window?.touchBar = bar
    }

    func update(network: NetworkInfo, cpu: CPUInfo, fans: [FanInfo], temperature: Double?) {
        networkTitle = "↓\(Self.shortSpeed(network.inRate)) ↑\(Self.shortSpeed(network.outRate))"
        cpuTitle = "CPU \(Int(cpu.overall.rounded()))%"
        fanTitle = fans.first.map { "风扇 \($0.currentRPM)" } ?? "风扇 --"
        temperatureTitle = temperature.map { "温度 \(Int($0.rounded()))°" } ?? "温度 --°"

        buttons[Item.network]?.title = networkTitle
        buttons[Item.cpu]?.title = cpuTitle
        buttons[Item.fan]?.title = fanTitle
        buttons[Item.temperature]?.title = temperatureTitle
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
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
        item.view = button
        item.customizationLabel = title
        buttons[identifier] = button
        return item
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
}
