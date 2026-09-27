import SwiftUI

struct ToolkitView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var processMonitor: ProcessMonitor
    @ObservedObject var toolStore: ToolStore
    @ObservedObject var toolManager: ToolManager
    @ObservedObject var tempSensor: TempSensorService
    @ObservedObject var ruleEngine: RuleEngine
    @ObservedObject var scrollEnhancer: ScrollEnhancer
    var dockIcon: Binding<Bool>? = nil

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                tabButton("监控", icon: "chart.line.uptrend.xyaxis", tag: 0)
                tabButton("进程", icon: "square.stack.3d.up", tag: 1)
                tabButton("工具", icon: "wrench.and.screwdriver", tag: 2)
                tabButton("规则", icon: "bell.badge", tag: 3)
                Spacer()
                if let dockIcon {
                    Toggle("Dock 图标", isOn: dockIcon)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 11))
                }
                Text("开机 \(Format.duration(monitor.uptime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)

            Group {
                switch selectedTab {
                case 0: DashboardView(monitor: monitor, tempSensor: tempSensor)
                case 1: ProcessListView(processMonitor: processMonitor)
                case 2: ToolsView(store: toolStore, manager: toolManager, scrollEnhancer: scrollEnhancer)
                default: RulesView(engine: ruleEngine)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, minHeight: 620)
    }

    private func tabButton(_ title: String, icon: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: selectedTab == tag ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == tag ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tag ? Color(nsColor: .quaternaryLabelColor) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var tempSensor: TempSensorService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cpuSection
                memorySection
                networkSection
                diskSection
                TemperatureCard(tempSensor: tempSensor)
            }
            .padding(14)
        }
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CPU", value: "\(Int(monitor.cpu.overall.rounded()))%")
            ChartView(values: monitor.cpuHistory, color: .blue) { value in
                "\(Int(value.rounded()))%"
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(monitor.cpu.perCore.enumerated()), id: \.offset) { index, usage in
                    VStack(spacing: 2) {
                        Text("\(index)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        Gauge(value: usage, in: 0...100) {
                            EmptyView()
                        } currentValueLabel: {
                            Text("\(Int(usage.rounded()))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(usage > 85 ? Color.red : .primary)
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("内存", value: "\(Format.bytesShort(monitor.memory.used)) / \(Format.bytes(monitor.memory.total))")
            let usedRatio = monitor.memory.total > 0 ? Double(monitor.memory.used) / Double(monitor.memory.total) : 0
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Gradient(colors: [.green, .yellow, .orange]))
                        .frame(width: max(proxy.size.width * usedRatio, usedRatio > 0 ? 6 : 0))
                }
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                memoryLegend("已用", monitor.memory.used, .primary)
                memoryLegend("缓存", monitor.memory.cached, .blue)
                memoryLegend("已压缩", monitor.memory.compressed, .orange)
                memoryLegend("空闲", monitor.memory.free, .secondary)
            }
            if monitor.memory.swapTotal > 0 {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Swap \(Format.bytesShort(monitor.memory.swapUsed)) / \(Format.bytesShort(monitor.memory.swapTotal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("网络", value: "")
            HStack(spacing: 10) {
                netIndicator(icon: "arrow.down.circle.fill", label: "下载", value: Format.speed(monitor.network.inRate), color: .blue)
                netIndicator(icon: "arrow.up.circle.fill", label: "上传", value: Format.speed(monitor.network.outRate), color: .green)
            }
            HStack(spacing: 8) {
                ChartView(values: monitor.netInHistory, color: .blue) { Format.speed($0) }
                ChartView(values: monitor.netOutHistory, color: .green) { Format.speed($0) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let freeRatio = monitor.disk.total > 0 ? 1 - Double(monitor.disk.free) / Double(monitor.disk.total) : 0
            sectionHeader("磁盘", value: "\(Format.bytesShort(monitor.disk.free)) 可用")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(freeRatio > 0.9 ? AnyShapeStyle(Color.red) : AnyShapeStyle(Gradient(colors: [.blue, .purple])))
                        .frame(width: max(proxy.size.width * freeRatio, freeRatio > 0 ? 4 : 0))
                }
            }
            .frame(height: 8)
            Text("共 \(Format.bytes(monitor.disk.total))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private func sectionHeader(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func memoryLegend(_ label: String, _ value: UInt64, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                Text(Format.bytesShort(value)).font(.system(size: 9, weight: .medium, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func netIndicator(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
    }
}

struct ChartView: View {
    let values: [Double]
    let color: Color
    let formatter: (Double) -> String

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let maxValue = max(values.max() ?? 1, 0.001)
            let stepX = size.width / max(Double(values.count - 1), 1)
            let points: [CGPoint] = values.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - CGFloat(value / maxValue) * (size.height - 2) - 1
                )
            }
            guard points.count > 1 else { return }

            var path = Path()
            path.move(to: CGPoint(x: points[0].x, y: size.height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.15)))

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() { line.addLine(to: point) }
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        }
        .frame(height: 44)
    }
}
