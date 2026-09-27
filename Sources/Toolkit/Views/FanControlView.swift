import SwiftUI

struct FanControlView: View {
    @ObservedObject var smc: SMCService
    @AppStorage("showFanInMenuBar") private var showFanInMenuBar = true
    @AppStorage("showTempInMenuBar") private var showTempInMenuBar = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = smc.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                if !smc.available {
                    Label("未检测到可读取的风扇。", systemImage: "fan.slash")
                        .font(.caption)
                } else {
                    HStack {
                        Toggle("菜单栏显示转速", isOn: $showFanInMenuBar)
                        Toggle("显示 CPU 温度", isOn: $showTempInMenuBar)
                    }
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    if !smc.helperInstalled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("风扇转速和温度可直接查看。修改转速需要安装特权助手。")
                                .font(.caption)
                            Button("安装风扇控制助手…") { smc.installHelper() }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(smc.fans) { fan in FanRow(fan: fan, smc: smc) }
                    sensorCard
                }
            }
            .padding(14)
        }
    }

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("温度传感器").font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(smc.sensors) { sensor in
                    HStack {
                        Text(sensor.name).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f°C", sensor.value))
                            .monospacedDigit()
                            .foregroundStyle(sensor.value > 85 ? .red : .primary)
                    }
                    .font(.system(size: 11))
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
    @State private var rpm: Double = 3000
    @State private var sensorKey = "TC0P"
    @State private var low = 45.0
    @State private var high = 80.0

    private var mode: Int {
        switch smc.settings[fan.id] {
        case .constant: return 1
        case .sensor: return 2
        default: return fan.manualMode ? 1 : 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "fanblades").foregroundStyle(.blue)
                Text(fan.name).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(fan.currentRPM) RPM").font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            Text("范围 \(fan.minRPM)–\(fan.maxRPM) RPM · 目标 \(fan.targetRPM) RPM")
                .font(.caption2).foregroundStyle(.secondary)
            Picker("控制方式", selection: Binding(get: { mode }, set: { selected in
                if selected == 0 { _ = smc.setSystemControl(fan: fan.id) }
                if selected == 1 { rpm = Double(max(fan.minRPM, min(fan.maxRPM, fan.targetRPM))); _ = smc.setConstantRPM(Int(rpm), fan: fan.id) }
                if selected == 2 { applySensorControl() }
            })) {
                Text("系统自动").tag(0)
                Text("固定转速").tag(1)
                Text("温度联动").tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(!smc.helperInstalled)
            if mode == 1 {
                HStack {
                    Slider(value: $rpm, in: Double(fan.minRPM)...Double(fan.maxRPM), step: 50) { editing in
                        if !editing { _ = smc.setConstantRPM(Int(rpm), fan: fan.id) }
                    }
                    Text("\(Int(rpm))").monospacedDigit().frame(width: 52)
                }
                .font(.caption)
                .onAppear { rpm = Double(fan.targetRPM) }
            }
            if mode == 2 {
                Picker("传感器", selection: $sensorKey) {
                    ForEach(smc.sensors) { sensor in Text(sensor.name).tag(sensor.id) }
                }
                HStack {
                    Text("最低温度")
                    TextField("°C", value: $low, format: .number).frame(width: 44)
                    Text("最高温度")
                    TextField("°C", value: $high, format: .number).frame(width: 44)
                    Button("应用") { applySensorControl() }
                }
                .font(.caption)
                Text("低于最低温度使用最低转速，高于最高温度使用最高转速。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                Capsule().fill(.quaternary).overlay(alignment: .leading) {
                    Capsule().fill(.blue).frame(width: geometry.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var ratio: Double {
        Double(max(0, fan.currentRPM - fan.minRPM)) / Double(max(1, fan.maxRPM - fan.minRPM))
    }

    private func applySensorControl() {
        guard sensorKey != "", high > low + 1 else { return }
        _ = smc.setSensorControl(fan: fan.id, sensor: sensorKey, low: low, high: high)
    }
}
