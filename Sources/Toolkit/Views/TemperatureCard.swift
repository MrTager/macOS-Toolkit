import SwiftUI

struct TemperatureCard: View {
    @ObservedObject var tempSensor: TempSensorService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            if tempSensor.available {
                ForEach(tempSensor.readings) { reading in
                    row(reading)
                }
            } else {
                Text("未检测到可用传感器")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private var sectionHeader: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 12))
                Text("温度").font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            if let battery = tempSensor.batteryTemperature {
                Text(String(format: "电池 %.1f°C", battery))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ reading: SensorReading) -> some View {
        HStack {
            Text(reading.name)
                .font(.system(size: 12))
            Spacer()
            if reading.unit == "°C" {
                temperatureBadge(reading.value)
            } else {
                pressureBadge(reading.value)
            }
        }
    }

    private func temperatureBadge(_ value: Double) -> some View {
        let color: Color = value < 40 ? .green : (value < 55 ? .orange : .red)
        return Text(String(format: "%.1f°C", value))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
    }

    private func pressureBadge(_ score: Double) -> some View {
        let labels: [(Double, String, Color)] = [
            (0, "正常", .green), (25, "良好", .green), (50, "偏高", .orange),
            (75, "严重", .red)
        ]
        let matched = labels.last { score >= $0.0 } ?? labels[0]
        return HStack(spacing: 4) {
            Circle().fill(matched.2).frame(width: 6, height: 6)
            Text(matched.1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(matched.2)
        }
    }
}
