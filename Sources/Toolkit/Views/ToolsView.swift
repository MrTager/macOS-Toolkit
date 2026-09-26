import SwiftUI

struct ToolsView: View {
    @ObservedObject var manager: ToolManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let message = manager.lastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(manager.tools) { tool in
                    ToolRow(tool: tool, manager: manager)
                }
            }
            .padding(14)
        }
    }
}

private struct ToolRow: View {
    let tool: ManagedTool
    @ObservedObject var manager: ToolManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.glyph")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.system(size: 12, weight: .medium))
                Text(tool.description).font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Spacer()

            if manager.isRunning(tool) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("运行中")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            } else {
                Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                Text("未运行")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button {
                manager.toggle(tool)
            } label: {
                Text(manager.isRunning(tool) ? "停止" : "启动")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            manager.isRunning(tool) ? Color.red.opacity(0.15) : Color.blue.opacity(0.15)
                        )
                    )
                    .foregroundStyle(manager.isRunning(tool) ? .red : .blue)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background).shadow(radius: 0.5))
    }
}
