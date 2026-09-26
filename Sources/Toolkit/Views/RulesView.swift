import SwiftUI

struct RulesView: View {
    @ObservedObject var engine: RuleEngine
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("阈值告警")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("添加规则")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(.quaternary).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(engine.rules) { rule in
                        RuleRow(rule: rule, engine: engine)
                    }

                    if !engine.lastEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("最近事件")
                                .font(.system(size: 11, weight: .semibold))
                            ForEach(engine.lastEvents.prefix(8), id: \.self) { event in
                                Text(event)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3)))
                    }
                }
                .padding(14)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            RuleEditSheet(engine: engine, rule: nil)
        }
    }
}

private struct RuleRow: View {
    let rule: AlertRule
    @ObservedObject var engine: RuleEngine
    @State private var showEdit = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in engine.toggle(rule) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.metric.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Text(String(format: "≥ %.0f%@ · 冷却 %d 分钟", rule.threshold, rule.metric.unit, rule.cooldownMinutes))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let current = engine.lastCheckResult[rule.metric] {
                Text(String(format: "%.0f%@", current, rule.metric.unit))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(current >= rule.threshold && rule.enabled ? .red : .secondary)
                    .help("当前值")
            }

            Button {
                showEdit = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                engine.remove(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background).shadow(radius: 0.5))
        .opacity(rule.enabled ? 1 : 0.55)
        .sheet(isPresented: $showEdit) {
            RuleEditSheet(engine: engine, rule: rule)
        }
    }
}

private struct RuleEditSheet: View {
    @ObservedObject var engine: RuleEngine
    let rule: AlertRule?
    @Environment(\.dismiss) private var dismiss
    @State private var metric: RuleMetric = .cpu
    @State private var threshold: Double = 90
    @State private var cooldown: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rule == nil ? "添加告警规则" : "编辑告警规则")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("指标").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("", selection: $metric) {
                    ForEach(RuleMetric.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "阈值：%.0f%@", threshold, metric.unit))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $threshold, in: thresholdRange, step: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "告警冷却：%.0f 分钟", cooldown))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $cooldown, in: 1...60, step: 1)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(rule == nil ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            if let rule {
                metric = rule.metric
                threshold = rule.threshold
                cooldown = Double(rule.cooldownMinutes)
            } else {
                threshold = metric.defaultThreshold
            }
        }
        .onChange(of: metric) { newValue in
            threshold = newValue.defaultThreshold
        }
    }

    private var thresholdRange: ClosedRange<Double> {
        switch metric {
        case .cpu, .memory: return 50...100
        case .batteryTemp: return 30...60
        case .thermalPressure: return 25...75
        }
    }

    private func save() {
        var managed = rule ?? AlertRule(metric: metric, threshold: threshold)
        managed.metric = metric
        managed.threshold = threshold
        managed.cooldownMinutes = Int(cooldown)
        if rule == nil {
            engine.add(managed)
        } else {
            engine.update(managed)
        }
        dismiss()
    }
}
