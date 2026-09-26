import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    private let monitor = SystemMonitor()
    private let processMonitor = ProcessMonitor()
    private let toolStore = ToolStore()
    private let toolManager: ToolManager
    private let tempSensor = TempSensorService()
    private let ruleEngine = RuleEngine()
    let scrollEnhancer = ScrollEnhancer()

    override init() {
        toolManager = ToolManager(toolStore: toolStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        popover.contentSize = NSSize(width: 420, height: 620)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ToolkitView(
                monitor: monitor,
                processMonitor: processMonitor,
                toolStore: toolStore,
                toolManager: toolManager,
                tempSensor: tempSensor,
                ruleEngine: ruleEngine,
                scrollEnhancer: scrollEnhancer
            )
        )

        monitor.$statusText
            .combineLatest(monitor.$cpu)
            .receive(on: RunLoop.main)
            .sink { [weak self] text, cpu in
                guard let button = self?.statusItem?.button else { return }
                let color: NSColor = cpu.overall < 60 ? .systemGreen : (cpu.overall < 90 ? .systemYellow : .systemRed)
                button.attributedTitle = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: color
                    ]
                )
            }
            .store(in: &cancellables)

        monitor.start()
        processMonitor.start()
        toolManager.start()
        tempSensor.start()
        ruleEngine.configure(monitor: monitor, tempSensor: tempSensor)
        ruleEngine.start()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "退出 Toolkit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem?.menu = nil }
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
