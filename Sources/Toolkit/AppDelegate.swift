import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    @Published private var dockIconVisible = false {
        didSet {
            NSApp.setActivationPolicy(dockIconVisible ? .regular : .accessory)
        }
    }

    var dockIconBinding: Binding<Bool> {
        Binding(get: { self.dockIconVisible }, set: { self.dockIconVisible = $0 })
    }

    private let monitor = SystemMonitor()
    private let processMonitor = ProcessMonitor()
    private let toolStore = ToolStore()
    private let toolManager: ToolManager
    private let tempSensor = TempSensorService()
    private let ruleEngine = RuleEngine()
    let scrollEnhancer = ScrollEnhancer()
    private let smcService = SMCService()
    private lazy var touchBarController = TouchBarController { [weak self] in
        self?.showMainWindow()
    }

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

        popover.contentSize = NSSize(width: 500, height: 620)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ToolkitView(
                monitor: monitor,
                processMonitor: processMonitor,
                toolStore: toolStore,
                toolManager: toolManager,
                tempSensor: tempSensor,
                ruleEngine: ruleEngine,
                scrollEnhancer: scrollEnhancer,
                dockIcon: dockIconBinding,
                smc: smcService
            )
            .frame(width: 500)
        )

        setupMainWindow()
        touchBarController.install(on: mainWindow)
        smcService.start()

        monitor.$network
            .combineLatest(monitor.$cpu, smcService.$fans, smcService.$sensors)
            .combineLatest(monitor.$memory, monitor.$disk)
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics, memory, disk in
                let (network, cpu, fans, sensors) = metrics
                let temperature = sensors.first(where: { $0.id == "TC0P" })?.value
                    ?? sensors.first(where: { $0.id.hasPrefix("TC") })?.value
                self?.touchBarController.update(
                    network: network, cpu: cpu, fans: fans, temperature: temperature,
                    memory: memory, disk: disk
                )
            }
            .store(in: &cancellables)

        monitor.$statusText
            .combineLatest(monitor.$cpu, smcService.$fans, smcService.$sensors)
            .receive(on: RunLoop.main)
            .sink { [weak self] text, cpu, fans, sensors in
                guard let button = self?.statusItem?.button else { return }
                let color: NSColor = cpu.overall < 60 ? .systemGreen : (cpu.overall < 90 ? .systemYellow : .systemRed)
                var title = text
                if UserDefaults.standard.object(forKey: "showFanInMenuBar") as? Bool ?? true,
                   let fan = fans.first {
                    title += "  F\(fan.id + 1) \(fan.currentRPM)"
                }
                if UserDefaults.standard.bool(forKey: "showTempInMenuBar"),
                   let sensor = sensors.first(where: { $0.id == "TC0P" }) {
                    title += "  \(Int(sensor.value))°"
                }
                button.attributedTitle = NSAttributedString(
                    string: title,
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(touchBarDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if !self.touchBarController.presentPersistent() {
                NSLog("Toolkit persistent Touch Bar unavailable; app controls remain active")
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "打开主窗口", action: #selector(showMainWindow), keyEquivalent: "n")
            menu.addItem(
                withTitle: "在 Dock 显示图标",
                action: #selector(toggleDockIcon),
                keyEquivalent: "d"
            )
            if let item = menu.items.last {
                item.state = dockIconVisible ? .on : .off
            }
            menu.addItem(.separator())
            menu.addItem(
                withTitle: "显示常驻 Touch Bar", action: #selector(showPersistentTouchBar), keyEquivalent: ""
            ).target = self
            menu.addItem(
                withTitle: "恢复系统 Touch Bar", action: #selector(dismissPersistentTouchBar), keyEquivalent: ""
            ).target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出 Toolkit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem?.menu = nil }
        } else if event.type == .otherMouseUp {
            showMainWindow()
        } else {
            togglePopover(sender)
        }
    }

    @objc private func toggleDockIcon() {
        dockIconVisible.toggle()
        if dockIconVisible {
            showMainWindow()
        }
    }

    @objc private func showPersistentTouchBar() {
        _ = touchBarController.presentPersistent()
    }

    @objc private func dismissPersistentTouchBar() {
        touchBarController.dismissPersistent()
    }

    @objc private func touchBarDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.touchBarController.restoreAfterWake()
        }
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            setupMainWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func setupMainWindow() {
        let contentView = ToolkitView(
            monitor: monitor,
            processMonitor: processMonitor,
            toolStore: toolStore,
            toolManager: toolManager,
            tempSensor: tempSensor,
            ruleEngine: ruleEngine,
            scrollEnhancer: scrollEnhancer,
            dockIcon: dockIconBinding,
            smc: smcService
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "macOS Toolkit"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.setContentSize(NSSize(width: 900, height: 680))
        window.isReleasedWhenClosed = false
        window.center()
        mainWindow = window
        if NSApp.touchBar != nil {
            touchBarController.install(on: window)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        touchBarController.uninstallPersistent()
        smcService.stop()
    }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            touchBarController.installOnPopover(popover)
        }
    }
}
