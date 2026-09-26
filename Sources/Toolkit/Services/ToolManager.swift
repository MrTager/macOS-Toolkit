import AppKit
import Combine
import Foundation
import ServiceManagement

struct ManagedTool: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleIdentifier: String?
    var description: String

    init(name: String, bundleIdentifier: String? = nil, description: String) {
        self.id = UUID()
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.description = description
    }
}

final class ToolStore: ObservableObject {
    @Published private(set) var tools: [ManagedTool] = []

    private static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("macOS Toolkit/tools.json")
    }

    init() {
        load()
        if tools.isEmpty {
            tools = Self.defaultTools
            save()
        }
    }

    static let defaultTools: [ManagedTool] = [
        ManagedTool(name: "Macs Fan Control", bundleIdentifier: "com.crystalidea.MacsFanControl", description: "风扇控制与温度监控"),
        ManagedTool(name: "Mos", bundleIdentifier: "com.caldis.Mos", description: "鼠标滚动平滑与方向反转"),
        ManagedTool(name: "Clash Verge", bundleIdentifier: "io.github.clash-verge-rev.clash-verge-rev", description: "网络代理"),
        ManagedTool(name: "Tencent Lemon", bundleIdentifier: "com.tencent.LemonLite", description: "系统清理"),
        ManagedTool(name: "CleanMyMac X", bundleIdentifier: "com.macpaw.CleanMyMac4", description: "深度清理"),
        ManagedTool(name: "Docker", bundleIdentifier: "com.docker.docker", description: "容器运行时"),
        ManagedTool(name: "Termius", bundleIdentifier: "com.termius.mac", description: "SSH 终端"),
        ManagedTool(name: "MacZip", bundleIdentifier: "com.tencent.MacZip", description: "压缩解压")
    ]

    func add(_ tool: ManagedTool) {
        tools.append(tool)
        save()
    }

    func update(_ tool: ManagedTool) {
        guard let index = tools.firstIndex(where: { $0.id == tool.id }) else { return }
        tools[index] = tool
        save()
    }

    func remove(id: UUID) {
        tools.removeAll { $0.id == id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        tools.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func reset() {
        tools = Self.defaultTools
        save()
    }

    private func load() {
        let url = Self.configURL
        guard let data = try? Data(contentsOf: url) else { return }
        if let loaded = try? JSONDecoder().decode([ManagedTool].self, from: data) {
            tools = loaded
        }
    }

    private func save() {
        let url = Self.configURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(tools) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

final class ToolManager: ObservableObject {
    @Published private(set) var runningState: [UUID: Bool] = [:]
    @Published private(set) var lastActionMessage: String?
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            toggleLaunchAtLogin()
        }
    }

    private var timer: Timer?
    private let toolStore: ToolStore

    init(toolStore: ToolStore) {
        self.toolStore = toolStore
    }

    func start() {
        refreshStates()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStates()
        }
    }

    func isRunning(_ tool: ManagedTool) -> Bool {
        runningState[tool.id] ?? false
    }

    func launch(_ tool: ManagedTool) {
        guard let bundleId = tool.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            lastActionMessage = "未找到 \(tool.name)"
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.lastActionMessage = error == nil ? "已启动 \(tool.name)" : "启动失败: \(error!.localizedDescription)"
            }
        }
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

    private func toggleLaunchAtLogin() {
        Task { @MainActor in
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastActionMessage = "开机自启设置失败: \(error.localizedDescription)"
                launchAtLogin.toggle()
            }
        }
    }

    private func refreshStates() {
        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var states: [UUID: Bool] = [:]
        for tool in toolStore.tools {
            if let bundleId = tool.bundleIdentifier {
                states[tool.id] = runningBundleIds.contains(bundleId)
            }
        }
        runningState = states
    }
}
