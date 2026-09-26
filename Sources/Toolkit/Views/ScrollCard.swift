import SwiftUI

struct ScrollCard: View {
    @ObservedObject var enhancer: ScrollEnhancer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magicmouse")
                    .font(.system(size: 12))
                Text("滚动增强")
                    .font(.system(size: 12, weight: .semibold))
                if enhancer.active {
                    Text("运行中")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { enhancer.settings.reverse || enhancer.settings.smooth },
                    set: { _ in enhancer.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!enhancer.permissionGranted)
                .help(enhancer.active ? "点击停止" : "点击启动")
            }

            if !enhancer.permissionGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("需要辅助功能权限")
                        .font(.system(size: 11))
                    Spacer()
                    Button("去授权") {
                        enhancer.openPermissionSettings()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.link)
                    Button("已授权") {
                        enhancer.refreshPermission()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.link)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
            }

            settingRow("方向反转", binding(\.reverse))
            settingRow("平滑滚动", binding(\.smooth))

            if enhancer.settings.smooth {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "滚动速度 %.2f", enhancer.settings.stepRatio))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: binding(\.stepRatio), in: 0.3...1.5, step: 0.05)
                        .controlSize(.mini)
                    Text(String(format: "动画时长 %.2f 秒", enhancer.settings.duration))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: binding(\.duration), in: 0.1...0.6, step: 0.05)
                        .controlSize(.mini)
                }
                .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private func settingRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { enhancer.settings[keyPath: keyPath] },
            set: { enhancer.settings[keyPath: keyPath] = $0 }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<ScrollSettings, Double>) -> Binding<Double> {
        Binding(
            get: { enhancer.settings[keyPath: keyPath] },
            set: { enhancer.settings[keyPath: keyPath] = $0 }
        )
    }
}
