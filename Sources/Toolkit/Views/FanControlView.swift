import SwiftUI

struct FanControlView: View {
    @ObservedObject var smc: SMCService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !smc.available {
                    unavailableCard
                } else {
                    fanCards
                    sensorCard
                }
            }
            .padding(14)
        }
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "fan.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("SMC 通道不可用")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("当前 macOS 版本对普通应用关闭了 SMC 直读通道（CPU die 温度、风扇转速需特权助手支持）。监控页仍提供电池温度与 CPU 热压力。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
    }

    private var fanCards: some View {
        ForEach(smc.fans) { fan in
            FanRow(fan: fan, smc: smc)
        }
    }

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("温度传感器")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let cpu = smc.cpuTemperature {
                    Text(String(format: "CPU %.1f°C", cpu))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(cpu > 90 ? .red : .secondary)
                }
            }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 6) {
                ForEach(smc.sensors.filter { $0.unit == "°C" }.prefix(16)) { sensor in
                    HStack {
                        Text(sensor.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f°", sensor.value))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(sensor.value > 85 ? .red : (sensor.value > 70 ? .orange : .primary))
                    }
                }
            }
            if !smc.sensors.filter({ $0.unit == "W" }).isEmpty {
                Rectangle().fill(.quaternary).frame(height: 1)
                ForEach(smc.sensors.filter { $0.unit == "W" }) { sensor in
                    HStack {
                        Text(sensor.name).font(.system(size: 11))
                        Spacer()
                        Text(String(format: "%.1f W", sensor.value))
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }
}

private struct FanRow: View {
    let fan: FanInfo
    @ObservedObject var smc: SMCService
    @State private var manualMode = false
    @State private var targetRPM: Double = 3000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "fanblades")
                    .font(.system(size: 14))
                    .foregroundStyle(fan.currentRPM > 4500 ? .red : .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fan.name).font(.system(size: 12, weight: .semibold))
                    Text("\(fan.minRPM)–\(fan.maxRPM) RPM")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(fan.currentRPM)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text("RPM")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                Toggle("", isOn: $manualMode)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: manualMode) { enabled in
                        if enabled {
                            targetRPM = Double(fan.currentRPM)
                            smc.setManualRPM(fan.currentRPM, fan: fan.id)
                        } else {
                            smc.setSystemControl()
                        }
                    }
            }

            if manualMode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "目标转速 %.0f RPM", targetRPM))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $targetRPM,
                        in: Double(fan.minRPM)...Double(fan.maxRPM),
                        step: 50
                    ) { editing in
                        if !editing {
                            smc.setManualRPM(Int(targetRPM), fan: fan.id)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Gradient(colors: [.blue, .cyan, .orange, .red]))
                        .frame(width: proxy.size.width * rpmRatio)
                }
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.4), value: fan.currentRPM)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var rpmRatio: CGFloat {
        let range = Double(fan.maxRPM - fan.minRPM)
        guard range > 0 else { return 0 }
        return CGFloat(max(0, min(1, (Double(fan.currentRPM) - Double(fan.minRPM)) / range)))
    }
}
