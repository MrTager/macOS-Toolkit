import SwiftUI

struct ToolsView: View {
    @ObservedObject var store: ToolStore
    @ObservedObject var manager: ToolManager
    @State private var editingTool: ManagedTool?
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle(isOn: $manager.launchAtLogin) {
                    Text("开机自启")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("添加工具")
                Button {
                    store.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("恢复默认列表")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(.quaternary).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let message = manager.lastActionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.tools) { tool in
                        ToolRow(tool: tool, manager: manager) {
                            editingTool = tool
                        } onDelete: {
                            store.remove(id: tool.id)
                        }
                    }
                    .onMove { source, destination in
                        store.move(from: source, to: destination)
                    }
                }
                .padding(14)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ToolEditSheet(store: store, tool: nil)
        }
        .sheet(item: $editingTool) { tool in
            ToolEditSheet(store: store, tool: tool)
        }
    }
}

private struct ToolRow: View {
    let tool: ManagedTool
    @ObservedObject var manager: ToolManager
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help("长按拖动排序")

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).font(.system(size: 12, weight: .medium))
                Text(tool.description.isEmpty ? (tool.bundleIdentifier ?? " ") : tool.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

            Menu {
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.vertical, 4)

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

private struct ToolEditSheet: View {
    @ObservedObject var store: ToolStore
    let tool: ManagedTool?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bundleId = ""
    @State private var description = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tool == nil ? "添加工具" : "编辑工具")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("名称").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("如：Macs Fan Control", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle ID").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("如：com.crystalidea.MacsFanControl", text: $bundleId)
                    .textFieldStyle(.roundedBorder)
                Text("提示：右键 App → 显示包内容 → Info.plist 中的 CFBundleIdentifier")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("描述").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("可选", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("从已安装应用选择…") {
                    pickApplication()
                }
                .font(.system(size: 11))
                .buttonStyle(.link)

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tool == nil ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if let tool {
                name = tool.name
                bundleId = tool.bundleIdentifier ?? ""
                description = tool.description
            }
        }
    }

    private func save() {
        let trimmed = bundleId.trimmingCharacters(in: .whitespaces)
        var managed = tool ?? ManagedTool(name: name, description: "")
        managed.name = name
        managed.bundleIdentifier = trimmed.isEmpty ? nil : trimmed
        managed.description = description
        if tool == nil {
            store.add(managed)
        } else {
            store.update(managed)
        }
        dismiss()
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url),
               let identifier = bundle.bundleIdentifier {
                bundleId = identifier
                if name.isEmpty {
                    name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }
}
