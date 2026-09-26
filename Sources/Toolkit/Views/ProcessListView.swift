import SwiftUI

struct ProcessListView: View {
    @ObservedObject var processMonitor: ProcessMonitor
    @State private var selectedPid: Int32?
    @State private var showKillConfirm = false
    @State private var forceKill = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索进程", text: $processMonitor.filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !processMonitor.filterText.isEmpty {
                    Button {
                        processMonitor.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 14)
                Picker("", selection: $processMonitor.sortBy) {
                    Image(systemName: "cpu").tag(ProcessMonitor.SortKey.cpu)
                    Image(systemName: "memorychip").tag(ProcessMonitor.SortKey.memory)
                    Image(systemName: "textformat").tag(ProcessMonitor.SortKey.name)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(.quaternary).frame(height: 1)

            Table(processMonitor.entries, selection: $selectedPid) {
                TableColumn("进程") { entry in
                    HStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(entry.name).font(.system(size: 12)).lineLimit(1)
                        Spacer().frame(width: 0)
                    }
                    .help("路径详情见下")
                }
                .width(min: 140, ideal: 170)

                TableColumn("PID") { entry in
                    Text("\(entry.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                .width(50)

                TableColumn("CPU") { entry in
                    Text(String(format: "%.1f%%", entry.cpu))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(entry.cpu > 70 ? .red : (entry.cpu > 30 ? .orange : .primary))
                }
                .width(60)

                TableColumn("内存") { entry in
                    Text(Format.bytesShort(entry.memory))
                        .font(.system(size: 11, design: .monospaced))
                }
                .width(70)

                TableColumn("用户") { entry in
                    Text(entry.user).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(70)
            }
            Rectangle().fill(.quaternary).frame(height: 1)

            HStack(spacing: 10) {
                Text("共 \(processMonitor.totalProcesses) 个进程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let pid = selectedPid, let entry = processMonitor.entries.first(where: { $0.pid == pid }) {
                    Text(entry.user)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        forceKill = false
                        showKillConfirm = true
                    } label: {
                        Text("结束")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .confirmationDialog(
            "结束进程 \(selectedName)?",
            isPresented: $showKillConfirm,
            titleVisibility: .visible
        ) {
            Button("结束 (SIGTERM)", role: .destructive) {
                if let pid = selectedPid { _ = processMonitor.terminate(pid, force: false) }
            }
            Button("强制结束 (SIGKILL)", role: .destructive) {
                if let pid = selectedPid { _ = processMonitor.terminate(pid, force: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("结束系统进程可能导致系统不稳定，请谨慎操作")
        }
    }

    private var selectedName: String {
        guard let pid = selectedPid, let entry = processMonitor.entries.first(where: { $0.pid == pid }) else {
            return ""
        }
        return entry.name
    }
}
// Fixed-height rows for the process Table
