import SwiftUI

/// 硬件资源轮询动态图表：CPU / 内存 / GPU
struct MonitorStrip: View {
    @EnvironmentObject private var monitor: HardwareMonitor

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            sparkline(
                title: "CPU",
                value: valueText(monitor.latest?.cpuTotal, suffix: "%"),
                color: .green,
                values: monitor.samples.map(\.cpuTotal),
                range: 0...1
            )
            sparkline(
                title: "内存",
                value: memoryText,
                color: .orange,
                values: monitor.samples.map { sample in
                    sample.memoryTotalGB > 0 ? sample.memoryUsedGB / sample.memoryTotalGB : 0
                },
                range: 0...1
            )
            sparkline(
                title: "GPU",
                value: gpuText,
                color: .purple,
                values: monitor.samples.map { $0.gpuUsage ?? 0 },
                range: 0...1
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.gpuName).font(.caption).lineLimit(1)
                Text(monitor.gpuUsageAvailable ? "GPU 利用率来自 IOAccelerator" : "系统未开放 GPU 利用率，显示显存占用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(String(format: "GPU 占用内存 %.2f GB", monitor.latest?.gpuMemoryGB ?? 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 210, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var memoryText: String {
        guard let sample = monitor.latest else { return "--" }
        return String(format: "%.1f / %.0f GB", sample.memoryUsedGB, sample.memoryTotalGB)
    }

    private var gpuText: String {
        guard let sample = monitor.latest, let usage = sample.gpuUsage else { return "--" }
        return String(format: "%.0f%%", usage * 100)
    }

    private func valueText(_ value: Double?, suffix: String) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f\(suffix)", value * 100)
    }

    private func sparkline(title: String, value: String, color: Color, values: [Double], range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.monospacedDigit()).bold()
            }
            Sparkline(values: values, range: range)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .background(
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.08))
                )
                .frame(width: 132, height: 34)
        }
    }
}

/// 只负责把一串比例值转成折线路径
struct Sparkline: Shape {
    let values: [Double]
    let range: ClosedRange<Double>
    let capacity: Int = 90

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let span = max(1, capacity - 1)
        let points = values.suffix(capacity)
        guard points.count > 1 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
        let lower = range.lowerBound
        let upper = max(range.upperBound, lower + 1e-6)
        let offset = capacity - points.count
        for (index, value) in points.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index + offset) / CGFloat(span)
            let normalized = min(max((value - lower) / (upper - lower), 0), 1)
            let y = rect.maxY - rect.height * CGFloat(normalized)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
