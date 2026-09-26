import AppKit
import Combine
import Foundation

struct ManagedTool: Identifiable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String?
    let path: String?
    let description: String

    init(name: String, bundleIdentifier: String? = nil, path: String? = nil, description: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.description = description
    }
}

final class ToolManager: ObservableObject {
    @Published private(set) var runningState: [String: Bool] = [:]
    @Published private(set) var lastActionMessage: String?

    private var timer: Timer?

    let tools: [ManagedTool] = [
        ManagedTool(
            name: "Macs Fan Control",
            bundleIdentifier: "com.crystalidea.MacsFanControl",
            description: "风扇控制与温度监控"
        ),
        ManagedTool(
            name: "Mos",
            bundleIdentifier: "com.caldis.Mos",
            description: "鼠标滚动平滑与方向反转"
        ),
        ManagedTool(
            name: "Clash Verge",
            bundleIdentifier: "io.github.clash-verge-rev.clash-verge-rev",
            description: "网络代理"
        ),
        ManagedTool(
            name: "Tencent Lemon",
            bundleIdentifier: "com.tencent.LemonLite",
            description: "系统清理"
        ),
        ManagedTool(
            name: "CleanMyMac X",
            bundleIdentifier: "com.macpaw.CleanMyMac4",
            description: "深度清理"
        ),
        ManagedTool(
            name: "Docker",
            bundleIdentifier: "com.docker.docker",
            description: "容器运行时"
        ),
        ManagedTool(
            name: "Termius",
            bundleIdentifier: "com.termius.mac",
            description: "SSH 终端"
        ),
        ManagedTool(
            name: "MacZip",
            bundleIdentifier: "com.tencent.MacZip",
            description: "压缩解压"
        )
    ]

    func start() {
        refreshStates()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStates()
        }
    }

    func isRunning(_ tool: ManagedTool) -> Bool {
        runningState[tool.id.uuidString] ?? false
    }

    func launch(_ tool: ManagedTool) {
        if let url = tool.path.map({ URL(fileURLWithPath: $0) }), FileManager.default.fileExists(atPath: tool.path!) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.lastActionMessage = error == nil ? "已启动 \(tool.name)" : "启动失败: \(error!.localizedDescription)"
                }
            }
            return
        }
        if let bundleId = tool.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            if tool.bundleIdentifier?.contains("docker") == true {
                config.arguments = []
            }
            NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.lastActionMessage = error == nil ? "已启动 \(tool.name)" : "启动失败: \(error!.localizedDescription)"
                }
            }
            return
        }
        lastActionMessage = "未找到 \(tool.name)"
    }

    func quit(_ tool: ManagedTool) {
        guard let bundleId = tool.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            lastActionMessage = "\(tool.name) 未在运行"
            return
        }
        app.terminate()
        lastActionMessage = "已发送退出指令 \(tool.name)"
    }

    func toggle(_ tool: ManagedTool) {
        if isRunning(tool) {
            quit(tool)
        } else {
            launch(tool)
        }
    }

    private func refreshStates() {
        var states: [String: Bool] = [:]
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap(\.bundleIdentifier))

        for tool in tools {
            if let bundleId = tool.bundleIdentifier {
                states[tool.id.uuidString] = runningBundleIds.contains(bundleId)
            } else if let path = tool.path {
                states[tool.id.uuidString] = NSWorkspace.shared.runningApplications
                    .contains { $0.bundleURL?.path == path }
            }
        }
        runningState = states
    }
}
